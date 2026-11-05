#include "cartorig.hpp"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>
int main(int argc,char **argv){try{
 if(argc!=5){std::cerr<<"Usage: cartorig_preview countries.geojson scene.json FRAME output.ppm\n";return 2;}
 auto dataset=cartorig::parseGeoJSON(cartorig::readText(argv[1]));auto scene=cartorig::parseScene(cartorig::readText(argv[2]));
 double frame=std::stod(argv[3]);const int w=640,h=360;std::vector<uint8_t> b(w*h*4,0);
 cartorig::View view;view.width=w;view.height=h;view.frame=frame;view.camera=evaluateCamera(scene,frame);
 cartorig::Surface out{b.data(),0,0,w,h,w*4,cartorig::PixelFormat::ByteRGBA};
 cartorig::render(scene,dataset,view,out);
 std::ofstream file(argv[4],std::ios::binary);if(!file)return 3;file<<"P6\n"<<w<<" "<<h<<"\n255\n";
 for(int y=h-1;y>=0;--y)for(int x=0;x<w;++x){auto *p=&b[(y*w+x)*4];file.write(reinterpret_cast<char*>(p),3);}if(!file)return 4;
 std::cout<<"Rendered "<<w<<"x"<<h<<", "<<dataset.features.size()<<" geography features\n";return 0;
 }catch(const std::exception &e){std::cerr<<"Render failed: "<<e.what()<<"\n";return 1;}}
