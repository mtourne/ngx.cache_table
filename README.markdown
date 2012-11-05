Name
====

ngx.cache_table - Simple Lua table with a ngx_lua caching layer.

Description
===========

This Lua library adds caching to Lua tables for ngx_lua, and ngx_openresty

http://wiki.nginx.org/HttpLuaModule

https://github.com/agentzh/ngx_openresty


Requirements
============
 * Nginx + lua-nginx-module
 * LuaJIT-2.0.0
 * cmgspack (luarocks install cmsgpack)


Synopsis
========

    lua_package_path    "/path/to/cache_table.lua;;";

    lua_shared_dict     cached_sessions     20M;

    server {
        location /test {
            content_by_lua '

            local cjson = require("cjson")

            local ip = 'xx.xx.xx.xx'

            -- init with empty values (optional)
            local my_table = { ip = "", session = "" }
            my_table = cache_table:new(60, ngx.shared.cached_sessions, my_table)

            -- load the table from shared_memory
            local my_table, cached = my_table:load("key")

            if not cached then
               -- cache MISS, refresh from memc, myslq, etc
               local memcached = require("resty.memcached")
               local memc, err = memcached:new()

               local ok, err = memc:connect("127.0.0.1", 11211)

               local res, flags, err = memc:get("session-" .. ip )

               my_table.ip = ip
               my_table.sesion = res

               -- save the table to shared memory
               my_table:save("key")
            end

            -- encode to json like a normal table
            ngx.say(cjson.encode(my_table))

            ';
        }
    }


Methods
=======

new
---
**syntax:** *cached_table, err = cache_table:new(ttl, shared_dict, base_table? opts?)*

Creates a cache_table

A cache_table provides methods, but is otherwise a full Lua table. Since it can't change the table itself, cached_table:load() returns a new cache_table

`ttl` caching_time set by save()
`shared_dict` a ngx.shared.DICT, declared in nginx.conf

If a bad shared_dict (undeclared in nginx.conf), the cache_table can't cache properly
and `err` will be set in the return

Optionally accepts `base_table`, and an `opts` table argument.

`opts.failed_ttl` will be used as to cache an "empty_entry",
when `cache_table:save(key, false)` is called


Common idiom :

    -- init the table (optional)
    local table = { value = "" }
    table = cache_table:new(ttl, shared_dict, table)

    local table, cached = table:load(key)

    if not cached then
       -- fetch from somewhere else

       -- save it
       table:save(key)

    end

new
---
**syntax:** *cached_table = cache_table:new(ttl, ngx.shared.DICT, [opts])*

Create a new cached_table.
This is a pure Lua table, all the magic lives in the metatable.

`ttl` : default caching ttl
`ngx.shared.DICT`: lua_shared_dict, defined in ngxinx.conf

`opts`: optional table

* `opts.failed_ttl`
    optionaly set a ttl for saving an entry with an empty table

load
----
**syntax:** *cached_table, cached = cache_table:load(key)*

Loads the table from a Ngx shared_memory, using `key`.

Always returns a table. If it was successfully fetched from cache,
`cached` is true.


save
----
**syntax:** *cached_table = cache_table:save(key, [good_lookup=true])*

Saves the table from a Ngx shared_memory, using `key`.

By default `good_lookup` is true. Optionally this can be set to false
to cache "empty entries" using `opts.failed_ttl`


See Also
========
* the ngx_lua module: http://wiki.nginx.org/HttpLuaModule
