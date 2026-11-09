#include "cartorig/labels.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace cartorig::rc1 {
namespace {
struct Mask {
 int width=0,height=0;
 std::vector<uint8_t> coverage;
 uint8_t at(int x,int y)const{
  if(x<0||y<0||x>=width||y>=height)return 0;
  return coverage[static_cast<std::size_t>(y)*width+x];
 }
};
#ifdef _WIN32
std::wstring utf16(const std::string&str){
 if(str.empty())return {};
 const int length=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,
       str.c_str(),static_cast<int>(str.size()),nullptr,0);
 if(length<=0)throw std::invalid_argument("Label requires valid UTF-8 text");
 std::wstring out(static_cast<std::size_t>(length),L'\0');
 if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,str.c_str(),
        static_cast<int>(str.size()),out.data(),length)!=length)
  throw std::invalid_argument("UTF-8 conversion failed");
 return out;
}
Mask textMask(const LabelOptions&label){
 auto text=utf16(label.text);
 const int size=std::clamp(static_cast<int>(std::lround(label.fontSize)),6,200);
 if(text.empty())return {};
 HDC dc=CreateCompatibleDC(nullptr);
 if(!dc)throw std::runtime_error("Windows text raster DC unavailable");
 HFONT font=nullptr;HBITMAP bitmap=nullptr;
 HGDIOBJ oldFont=nullptr,oldBitmap=nullptr;
 Mask mask;
 try{
  const auto family=label.fontFamily=="Sans"?"Segoe UI":label.fontFamily;
  auto wFamily=utf16(family);
  font=CreateFontW(-size,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,
                   DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,
                   ANTIALIASED_QUALITY,DEFAULT_PITCH,wFamily.c_str());
  if(!font)throw std::runtime_error("Windows text font not available");
  oldFont=SelectObject(dc,font);
  SIZE box{};
  if(!GetTextExtentPoint32W(dc,text.c_str(),static_cast<int>(text.size()),&box))
   throw std::runtime_error("Cannot measure text");
  mask.width=std::clamp(static_cast<int>(box.cx)+8,1,8192);
  mask.height=std::clamp(static_cast<int>(box.cy)+8,1,512);
  BITMAPINFO b{};
  b.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
  b.bmiHeader.biWidth=mask.width;
  b.bmiHeader.biHeight=-mask.height; // top-down bitmap
  b.bmiHeader.biPlanes=1;
  b.bmiHeader.biBitCount=32;
  b.bmiHeader.biCompression=BI_RGB;
  void* pixels=nullptr;
  bitmap=CreateDIBSection(dc,&b,DIB_RGB_COLORS,&pixels,nullptr,0);
  if(!bitmap||!pixels)throw std::runtime_error("Windows text bitmap unavailable");
  oldBitmap=SelectObject(dc,bitmap);
  PatBlt(dc,0,0,mask.width,mask.height,BLACKNESS);
  SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(255,255,255));
  if(!TextOutW(dc,4,4,text.c_str(),static_cast<int>(text.size())))
   throw std::runtime_error("Windows native text rasterization failed");
  GdiFlush();
  const auto*bytes=static_cast<const uint8_t*>(pixels);
  mask.coverage.resize(static_cast<std::size_t>(mask.width)*mask.height);
  for(std::size_t i=0;i<mask.coverage.size();++i)
   mask.coverage[i]=std::max(bytes[i*4],std::max(bytes[i*4+1],bytes[i*4+2]));
 }catch(...){
  if(oldBitmap)SelectObject(dc,oldBitmap);
  if(oldFont)SelectObject(dc,oldFont);
  if(bitmap)DeleteObject(bitmap);
  if(font)DeleteObject(font);
  DeleteDC(dc);
  throw;
 }
 if(oldBitmap)SelectObject(dc,oldBitmap);
 if(oldFont)SelectObject(dc,oldFont);
 if(bitmap)DeleteObject(bitmap);
 if(font)DeleteObject(font);
 DeleteDC(dc);
 return mask;
}
#else
// Portable fallback for core unit tests and headless builds; production
// Windows uses GDI rasterization with genuine installed Unicode fonts.
Mask textMask(const LabelOptions&label){
 const int s=std::max(1,static_cast<int>(label.fontSize/8));
 const int width=std::min(8192,static_cast<int>(label.text.size())*6*s+2*s);
 const int height=9*s;
 Mask m{width,height,{}};
 m.coverage.resize(static_cast<std::size_t>(width)*height);
 for(std::size_t i=0;i<label.text.size();++i){
  auto c=static_cast<unsigned char>(label.text[i]);
  if(c==' ')continue;
  // Deterministic, non-linguistic placeholder for non-Windows unit tests.
  for(int yy=0;yy<7*s;++yy)for(int xx=0;xx<5*s;++xx){
   bool border=(xx<s||yy<s||xx>=4*s||yy>=6*s);
   bool center=((c>>(yy/s)%7)&1) && xx/s==2;
   if(border||center){
    const int px=static_cast<int>(i)*6*s+xx,py=yy+s;
    if(px<width)m.coverage[static_cast<std::size_t>(py)*width+px]=255;
   }
  }
 }
 return m;
}
#endif
}
void drawLabel(Surface&canvas,const Camera&camera,const LabelOptions&label){
 camera.validate();
 if(label.text.size()>1000||!std::isfinite(label.fontSize)||label.fontSize<6||
    label.fontSize>200||!std::isfinite(label.opacity)||
    label.opacity<0||label.opacity>1||
    !std::isfinite(label.haloWidth)||label.haloWidth<0||label.haloWidth>20||
    !std::isfinite(label.offsetX)||!std::isfinite(label.offsetY)||
    std::abs(label.offsetX)>1000||std::abs(label.offsetY)>1000)
  throw std::invalid_argument("Invalid Label controls");
 if(label.text.empty()||label.opacity==0)return;
 auto mask=textMask(label);
 if(mask.coverage.empty())return;
 const auto anchor=project(label.at,camera,canvas.width,canvas.height);
 double x=anchor.x+label.offsetX;
 if(label.alignment==TextAlign::Center)x-=mask.width*.5;
 if(label.alignment==TextAlign::Right)x-=mask.width;
 const double y=anchor.y+label.offsetY-mask.height*.5;
 const int originX=static_cast<int>(std::lround(x));
 const int originY=static_cast<int>(std::lround(y));
 const int halo=label.halo?static_cast<int>(std::ceil(label.haloWidth)):0;
 const int left=std::max(0,-originX-halo),top=std::max(0,-originY-halo);
 const int right=std::min(mask.width,canvas.width-originX+halo);
 const int bottom=std::min(mask.height,canvas.height-originY+halo);
 for(int py=top;py<bottom;++py)for(int px=left;px<right;++px){
  const uint8_t cov=mask.at(px,py);
  if(cov==0)continue;
  if(halo>0){
   for(int dy=-halo;dy<=halo;++dy)for(int dx=-halo;dx<=halo;++dx){
    if(dx*dx+dy*dy>label.haloWidth*label.haloWidth)continue;
    canvas.blend(originX+px+dx,originY+py+dy,label.haloColor,
                 label.opacity*(cov/255.));
   }
  }
  canvas.blend(originX+px,originY+py,label.fill,
               label.opacity*(cov/255.));
 }
}
} // namespace cartorig::rc1
