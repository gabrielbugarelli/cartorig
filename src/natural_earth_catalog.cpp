#include "natural_earth_catalog.hpp"
#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <utility>
#ifdef _WIN32
# define WIN32_LEAN_AND_MEAN
# include <windows.h>
#else
# include <dlfcn.h>
#endif

namespace cartorig {
namespace {
struct sqlite3;
struct sqlite3_stmt;
constexpr int SQLITE_OK_=0,SQLITE_ROW_=100,SQLITE_DONE_=101;
constexpr int SQLITE_OPEN_READONLY_=0x00000001;
constexpr int SQLITE_OPEN_NOMUTEX_=0x00008000;
struct SqliteApi {
#ifdef _WIN32
  HMODULE module=nullptr;
#else
  void *module=nullptr;
#endif
  int (*open_v2)(const char*,sqlite3**,int,const char*)=nullptr;
  int (*close_v2)(sqlite3*)=nullptr;
  int (*prepare_v2)(sqlite3*,const char*,int,sqlite3_stmt**,const char**)=nullptr;
  int (*bind_text)(sqlite3_stmt*,int,const char*,int,void(*)(void*))=nullptr;
  int (*step)(sqlite3_stmt*)=nullptr;
  const unsigned char* (*column_text)(sqlite3_stmt*,int)=nullptr;
  std::int64_t (*column_int64)(sqlite3_stmt*,int)=nullptr;
  int (*finalize)(sqlite3_stmt*)=nullptr;
  const char* (*errmsg)(sqlite3*)=nullptr;
  SqliteApi(){
#ifdef _WIN32
    // Do not search the current directory or PATH for an untrusted DLL.
    // WinSQLite3 is present in the Windows 10/11 system directory.
    module=LoadLibraryExW(L"winsqlite3.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
#else
    module=dlopen("libsqlite3.so.0",RTLD_NOW|RTLD_LOCAL);
    if(!module)module=dlopen("libsqlite3.so",RTLD_NOW|RTLD_LOCAL);
#endif
    if(!module)throw std::runtime_error("SQLite3 runtime unavailable; install the offline data pack");
#define LOAD_SYMBOL(member,symbol) do { \
      member=reinterpret_cast<decltype(member)>(load(symbol)); \
      if(!member)throw std::runtime_error("SQLite3 API missing: " symbol); \
    }while(false)
    try {
      LOAD_SYMBOL(open_v2,"sqlite3_open_v2");
      LOAD_SYMBOL(close_v2,"sqlite3_close_v2");
      LOAD_SYMBOL(prepare_v2,"sqlite3_prepare_v2");
      LOAD_SYMBOL(bind_text,"sqlite3_bind_text");
      LOAD_SYMBOL(step,"sqlite3_step");
      LOAD_SYMBOL(column_text,"sqlite3_column_text");
      LOAD_SYMBOL(column_int64,"sqlite3_column_int64");
      LOAD_SYMBOL(finalize,"sqlite3_finalize");
      LOAD_SYMBOL(errmsg,"sqlite3_errmsg");
    }catch(...){unload();throw;}
#undef LOAD_SYMBOL
  }
  ~SqliteApi(){unload();}
  void unload() noexcept{
    if(!module)return;
#ifdef _WIN32
    FreeLibrary(module);
#else
    dlclose(module);
#endif
    module=nullptr;
  }
  void* load(const char* name){
#ifdef _WIN32
    return reinterpret_cast<void*>(GetProcAddress(module,name));
#else
    return dlsym(module,name);
#endif
  }
  SqliteApi(const SqliteApi&)=delete;
  SqliteApi& operator=(const SqliteApi&)=delete;
};
std::string searchTerm(const std::string &text){
  if(text.size()>120)throw std::invalid_argument("search query too long");
  std::vector<std::string> tokens;
  std::string token;
  auto flush=[&]{
    if(token.empty())return;
    tokens.push_back(std::move(token));
    token.clear();
  };
  for(unsigned char c:text){
    if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||
       (c>='0'&&c<='9')||c>=128){
      token.push_back(static_cast<char>(c));
    }else flush();
  }
  flush();
  if(tokens.size()>8)throw std::invalid_argument("too many search words");
  std::string result;
  for(const auto &t:tokens){
    if(!result.empty())result+=" AND ";
    result+="\""+t+"\"*";
  }
  return result;
}
std::string str(const SqliteApi&api,sqlite3_stmt*stmt,int col){
  const auto p=api.column_text(stmt,col);
  return p?std::string(reinterpret_cast<const char*>(p)):std::string{};
}
struct DB {
  const SqliteApi &a;
  sqlite3 *db=nullptr;
  DB(const SqliteApi &api,const std::filesystem::path &path):a(api){
    if(path.empty()||!std::filesystem::is_regular_file(path))
      throw std::invalid_argument("Natural Earth index file not found");
    const std::string utf8=path.u8string();
    const int rc=a.open_v2(utf8.c_str(),&db,SQLITE_OPEN_READONLY_|SQLITE_OPEN_NOMUTEX_,nullptr);
    if(rc!=SQLITE_OK_) {
      std::string error=db?a.errmsg(db):"unable to open file";
      if(db)a.close_v2(db);
      db=nullptr;
      throw std::runtime_error("Natural Earth catalog failed to open: "+error);
    }
  }
  ~DB(){if(db)a.close_v2(db);}
  DB(const DB&)=delete;
  DB& operator=(const DB&)=delete;
};
struct Stmt {
  const SqliteApi &a;
  sqlite3_stmt*statement=nullptr;
  Stmt(const SqliteApi &api,sqlite3*db,const char*sql):a(api){
    if(a.prepare_v2(db,sql,-1,&statement,nullptr)!=SQLITE_OK_)
      throw std::runtime_error("Natural Earth SQLite schema mismatch");
  }
  ~Stmt(){if(statement)a.finalize(statement);}
  void bind(int index,const std::string &value){
    if(a.bind_text(statement,index,value.c_str(),static_cast<int>(value.size()),nullptr)!=SQLITE_OK_)
      throw std::runtime_error("Natural Earth search parameter binding failed");
  }
};
} // namespace

std::vector<NaturalEarthRegion> NaturalEarthCatalog::search(
    const std::filesystem::path &database,const std::string &text,
    const std::string &kind,int limit){
  if(kind!="country"&&kind!="state"&&kind!="city"&&kind!="continent")
    throw std::invalid_argument("invalid geographic category");
  if(limit<1||limit>50)throw std::invalid_argument("invalid search limit");
  const auto term=searchTerm(text);
  if(term.empty())return {};
  SqliteApi api;
  DB db(api,database);
  static constexpr const char*query=R"SQL(
    SELECT r.feature_key,r.kind,r.display_name,r.parent_name,r.geometry_type,
           r.source_layer,r.source_rowid,r.scale
    FROM search_fts JOIN regions r
      ON r.region_id=CAST(search_fts.region_id AS INTEGER)
    WHERE search_fts MATCH ? AND r.kind=?
    ORDER BY bm25(search_fts),
      CASE r.scale WHEN '10m' THEN 0 WHEN '50m' THEN 1
                   WHEN '110m' THEN 2 ELSE 3 END,
      r.display_name LIMIT 400
  )SQL";
  Stmt queryStmt(api,db.db,query);
  queryStmt.bind(1,term);queryStmt.bind(2,kind);
  std::vector<NaturalEarthRegion> matches;
  std::unordered_set<std::string> duplicates;
  int status=SQLITE_DONE_;
  while((status=api.step(queryStmt.statement))==SQLITE_ROW_){
    NaturalEarthRegion r;
    r.featureKey=str(api,queryStmt.statement,0);
    r.kind=str(api,queryStmt.statement,1);
    r.name=str(api,queryStmt.statement,2);
    r.parent=str(api,queryStmt.statement,3);
    r.geometryType=str(api,queryStmt.statement,4);
    r.sourceLayer=str(api,queryStmt.statement,5);
    r.sourceRowId=api.column_int64(queryStmt.statement,6);
    r.scale=str(api,queryStmt.statement,7);
    r.hasGeometry=r.geometryType!="DERIVED_GROUP_ONLY";
    const auto stable=r.kind+"|"+r.name+"|"+r.parent;
    if(!duplicates.insert(stable).second)continue;
    matches.push_back(std::move(r));
    if(static_cast<int>(matches.size())>=limit)break;
  }
  if(status!=SQLITE_DONE_&&status!=SQLITE_ROW_)
    throw std::runtime_error(std::string("Natural Earth FTS query failed: ")+api.errmsg(db.db));
  return matches;
}
} // namespace cartorig
