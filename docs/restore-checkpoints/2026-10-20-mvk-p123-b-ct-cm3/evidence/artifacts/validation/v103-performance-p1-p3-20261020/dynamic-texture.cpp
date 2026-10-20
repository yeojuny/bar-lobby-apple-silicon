
#include <cassert>
#include <cstdio>
#include <string>
#include <map>
#include <vector>
struct lua_State {};
struct CountingMap:std::map<std::string,size_t>{mutable int lookups=0;auto find(const std::string& n)const{++lookups;return std::map<std::string,size_t>::find(n);}};
struct LuaTextures {struct Texture{int id=0;};CountingMap textureMap;std::vector<Texture> textureVec;size_t GetIdx(const std::string&)const;
const Texture* GetInfo(size_t texIdx) const { return ((texIdx < textureVec.size())? &textureVec[texIdx]: nullptr); }
const Texture* GetInfo(const std::string& name) const { return (GetInfo(GetIdx(name))); }
};
size_t LuaTextures::GetIdx(const std::string& name) const
{
	const auto it = textureMap.find(name);

	if (it != textureMap.end())
		return (it->second);

	return (size_t(-1));
}
LuaTextures textures;
struct CLuaHandle{static const LuaTextures& GetActiveTextures(lua_State*){return textures;}};
struct LuaMatTexture {enum{LUATEX_NONE,LUATEX_LUATEXTURE};int type=LUATEX_NONE;const void* data=nullptr;};
bool before(LuaMatTexture& texUnit,lua_State* L,const std::string& image){

			if (L == nullptr)
				return false;

			// dynamic texture
			const LuaTextures& textures = CLuaHandle::GetActiveTextures(L);
			const LuaTextures::Texture* texInfo = textures.GetInfo(image);

			if (texInfo == nullptr)
				return false;

			texUnit.type = LuaMatTexture::LUATEX_LUATEXTURE;
			texUnit.data = reinterpret_cast<const void*>(textures.GetIdx(image));
		
return true;}
bool after(LuaMatTexture& texUnit,lua_State* L,const std::string& image){

			if (L == nullptr)
				return false;

			// dynamic texture
			const LuaTextures& textures = CLuaHandle::GetActiveTextures(L);
			const size_t texIdx = textures.GetIdx(image);
			const LuaTextures::Texture* texInfo = textures.GetInfo(texIdx);

			if (texInfo == nullptr)
				return false;

			texUnit.type = LuaMatTexture::LUATEX_LUATEXTURE;
			texUnit.data = reinterpret_cast<const void*>(texIdx);
		
return true;}
int main(){lua_State state;int cases=0;
for(int scenario=0;scenario<6;++scenario){textures.textureMap.clear();textures.textureVec.assign(2,{});lua_State* L=&state;
 if(scenario==0)textures.textureMap["!1"]=0;
 if(scenario==1)textures.textureMap["!1"]=1;
 if(scenario==3){textures.textureMap["!1"]=0;textures.textureMap.erase("!1");}
 if(scenario==4)textures.textureMap["!1"]=99;
 if(scenario==5)L=nullptr;
 LuaMatTexture a,b;textures.textureMap.lookups=0;bool ar=before(a,L,"!1");int oldCount=textures.textureMap.lookups;textures.textureMap.lookups=0;bool br=after(b,L,"!1");int newCount=textures.textureMap.lookups;
 assert(ar==br&&a.type==b.type&&a.data==b.data);assert(ar==(scenario<2));assert(newCount==(L?1:0));assert(oldCount==newCount+(ar?1:0));if(scenario==0)assert(br&&b.data==nullptr);++cases;
}printf("Dynamic texture extracted branch cases=%d passed\n",cases);}
