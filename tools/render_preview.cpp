#include "cartorig.hpp"
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>
int main(int argc,char **argv){try{
 if(argc!=5&&argc!=7){std::cerr<<"Usage: cartorig_preview countries.geojson scene.json FRAME output.ppm [WIDTH HEIGHT]\n";return 2;}
 auto dataset=cartorig::parseGeoJSON(cartorig::readText(argv[1]));auto scene=cartorig::parseScene(cartorig::readText(argv[2]));
 double frame=std::stod(argv[3]);const int w=argc==7?std::stoi(argv[5]):640,h=argc==7?std::stoi(argv[6]):360;
 if(w<=0||h<=0||w>7680||h>4320){std::cerr<<"Invalid output resolution\n";return 2;}
 std::vector<uint8_t> b(static_cast<size_t>(w)*h*4,0);
 cartorig::View view;view.width=w;view.height=h;view.frame=frame;view.camera=evaluateCamera(scene,frame);
 cartorig::Surface out{b.data(),0,0,w,h,w*4,cartorig::PixelFormat::ByteRGBA};
 auto start=std::chrono::steady_clock::now();cartorig::render(scene,dataset,view,out);
 auto elapsed=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count();
 std::ofstream file(argv[4],std::ios::binary);if(!file)return 3;file<<"P6\n"<<w<<" "<<h<<"\n255\n";
 std::vector<char> rgb(static_cast<size_t>(w)*3);
 for(int y=h-1;y>=0;--y){for(int x=0;x<w;++x){auto *p=&b[(static_cast<size_t>(y)*w+x)*4];rgb[x*3]=static_cast<char>(p[0]);rgb[x*3+1]=static_cast<char>(p[1]);rgb[x*3+2]=static_cast<char>(p[2]);}file.write(rgb.data(),static_cast<std::streamsize>(rgb.size()));}
 if(!file)return 4;
 std::cout<<"Rendered "<<w<<"x"<<h<<", "<<dataset.features.size()<<" geography features in "<<elapsed<<" ms\n";return 0;
 }catch(const std::exception &e){std::cerr<<"Render failed: "<<e.what()<<"\n";return 1;}}
