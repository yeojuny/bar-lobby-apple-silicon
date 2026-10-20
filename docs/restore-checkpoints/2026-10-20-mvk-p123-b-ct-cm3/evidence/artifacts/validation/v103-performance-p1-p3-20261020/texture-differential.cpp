
#include <cassert>
#include <cstdio>
#include <map>
#include <vector>
#include <string>
#include <tuple>
#define RECOIL_DETAILED_TRACY_ZONE
using GLboolean=bool;
constexpr int GL_LIST_INDEX=0;
bool inList=false,failLoad=false;
int queries=0,loads=0,inserts=0; bool secondary=false;
void glGetBooleanv(int,GLboolean* p){++queries;*p=inList;}
namespace CNamedTextures {
struct TexInfo {unsigned id=0; int xsize=-1,ysize=-1; unsigned texType=0;bool alpha=false,persist=false;};
std::map<std::string,size_t> texInfoMap;
std::vector<TexInfo> texInfoVec;
void GenInsertTex(const std::string& n,const TexInfo&,bool gen,bool bind,bool load,bool persist){
 assert(gen&&!load);++inserts;secondary=bind;TexInfo t;t.id=42;t.persist=persist;texInfoMap[n]=texInfoVec.size();texInfoVec.push_back(t);
}
bool GenLoadTex(const std::string& n){++loads;if(failLoad)return false;TexInfo t;t.id=43;texInfoMap[n]=texInfoVec.size();texInfoVec.push_back(t);return true;}
const TexInfo* GetInfo(const std::string&,bool,bool,bool,size_t&);
size_t GetInfoIndex(const std::string& texName)
	{
	RECOIL_DETAILED_TRACY_ZONE;
		const auto it = texInfoMap.find(texName);

		if (it != texInfoMap.end())
			return (it->second);

		return (size_t(-1));
	}
const TexInfo* GetInfoBefore(const std::string& texName, bool forceLoad, bool persist, bool secondaryGLContext)
	{
	RECOIL_DETAILED_TRACY_ZONE;
		if (texName.empty())
			return nullptr;

		const size_t texIdx = GetInfoIndex(texName);

		if (texIdx != size_t(-1)) {
			texInfoVec[texIdx].persist |= persist;
			return &texInfoVec[texIdx];
		}

		if (forceLoad) {
			// load texture
			GLboolean inListCompile;
			glGetBooleanv(GL_LIST_INDEX, &inListCompile);

			if (inListCompile) {
				GenInsertTex(texName, {}, true, secondaryGLContext, false, persist);
			} else {
				GenLoadTex(texName);
			}

			return &texInfoVec[ texInfoMap[texName] ];
		}

		return nullptr;
	}
const TexInfo* GetInfo(const std::string& texName, bool forceLoad, bool persist, bool secondaryGLContext, size_t& texIdx)
	{
	RECOIL_DETAILED_TRACY_ZONE;
		texIdx = size_t(-1);
		if (texName.empty())
			return nullptr;

		texIdx = GetInfoIndex(texName);

		if (texIdx != size_t(-1)) {
			texInfoVec[texIdx].persist |= persist;
			return &texInfoVec[texIdx];
		}

		if (forceLoad) {
			// load texture
			GLboolean inListCompile;
			glGetBooleanv(GL_LIST_INDEX, &inListCompile);

			if (inListCompile) {
				GenInsertTex(texName, {}, true, secondaryGLContext, false, persist);
			} else {
				GenLoadTex(texName);
			}

			texIdx = texInfoMap[texName];
			return &texInfoVec[texIdx];
		}

		return nullptr;
	}
const TexInfo* GetInfo(const std::string& texName, bool forceLoad, bool persist, bool secondaryGLContext)
	{
		size_t texIdx;
		return GetInfo(texName, forceLoad, persist, secondaryGLContext, texIdx);
	}
}
int main(){using namespace CNamedTextures;int cases=0;
for(int scenario=0;scenario<5;++scenario)for(bool force:{false,true})for(bool persist:{false,true})for(bool sec:{false,true})for(bool list:{false,true}) {
 auto setup=[&](){texInfoMap.clear();texInfoVec.assign(2,{});texInfoVec[0].id=17;texInfoVec[1].id=18;texInfoVec[1].persist=true;queries=loads=inserts=0;secondary=false;inList=list;failLoad=scenario==4;if(scenario==1)texInfoMap["image"]=0;if(scenario==2)texInfoMap["image"]=1;};
 const std::string name=scenario==0?"":"image";
 setup();const auto* before=GetInfoBefore(name,force,persist,sec);const size_t beforeIndex=before?GetInfoIndex(name):size_t(-1);const bool beforeNull=before==nullptr;const auto bm=texInfoMap;const auto bv=texInfoVec;const auto calls=std::make_tuple(queries,loads,inserts,secondary);
 setup();size_t index=123;const auto* after=GetInfo(name,force,persist,sec,index);
 assert((after==nullptr)==beforeNull);assert(index==beforeIndex);assert(texInfoMap==bm);assert(texInfoVec.size()==bv.size());assert(calls==std::make_tuple(queries,loads,inserts,secondary));
 for(size_t i=0;i<bv.size();++i){assert(texInfoVec[i].id==bv[i].id);assert(texInfoVec[i].persist==bv[i].persist);}
 if(after)assert(after==&texInfoVec[index]);
 // The original API remains available and delegates with identical effects.
 setup();const auto* legacy=GetInfo(name,force,persist,sec);assert((legacy==nullptr)==beforeNull);assert(texInfoMap==bm);assert(calls==std::make_tuple(queries,loads,inserts,secondary));
 ++cases;
}
printf("NamedTextures old/new differential cases=%d passed (GL/load calls stubbed)\n",cases);
}
