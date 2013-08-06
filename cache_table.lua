-- Copyright (C) 2012 Matthieu Tourne
-- @author Matthieu Tourne <matthieu@cloudflare.com>

-- Simple Cached table - Use with openresty or ngx_lua

-- A cache_table is a Full Lua table
-- All the magic for caching lives in the metatable

-- It can be serialized like a normal table (json etc)


-- Usage :

-- local my_table = { ip = 'xx.xx.xx.xx', session = "foo" }
-- my_table = cache_table:new(60, ngx.shared.cached_sessions, my_table)

-- local my_table, cached = my_table:load("key")

-- *Note:* this means that "self" is itself a table,
--    and self:load cannot change self itself.
--    cache_table:load() will always return a new instance.

local cmsgpack = require("cmsgpack")

local debug = require("debug")

-- Control caching for failed lookups
local DEFAULT_FAILED_LOOKUP_CACHE_TTL = 10

local DEBUG = false

local pack = cmsgpack.pack
local unpack = cmsgpack.unpack

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local cache_table = { }

local EMPTY_FLAG = 1

function cache_table.get_internal_table(self)
   local mt = getmetatable(self)
   return mt.__internal
end

function cache_table.get_internal(self, key)
   local mt = getmetatable(self)
   return mt.__internal[key]
end

function cache_table.set_internal(self, key, val)
   local mt = getmetatable(self)
   mt.__internal[key] = val
end

function cache_table.get_shared_dict(self)
   return self:get_internal('shared_dict')
end

-- cache_table:load(key)
-- Loads the table from a shared dict
-- @returns (loaded table, cached)
function cache_table.load(self, key)
   local shared_dict = self:get_shared_dict()
   local serialized, flags = shared_dict:get(key)

   if serialized then

      local mt = getmetatable(self)
      local internal = mt.__internal

      if DEBUG then
         internal['serialized'] = serialized
      end

      internal['serialized_size'] = #serialized

      local cache_status = 'HIT'
      if flags and flags == EMPTY_FLAG then
         -- cached empty
         cache_status = 'HIT_EMPTY'
      end

      internal['cache_status'] = cache_status

      local new_table = self:deserialize(serialized)
      setmetatable(new_table, mt)

      return new_table, true
   end

   return self, false
end

-- cache_table:save(key)
-- save an entry using the internal ttl
function cache_table.save(self, key)
   local ttl = self:get_internal('ttl')

   return self:save_ttl(key, ttl)
end

-- cache_table:save_empty(key)
-- save an empty slot for a shorter period (opts.ttl)
-- Use a flag in shmem to symbolize EMPTY
function cache_table.save_empty(self, key)
   local opts = self:get_internal('opts')
   local ttl = opts.failed_ttl

   return self:save_ttl(key, ttl, EMPTY_FLAG)
end

-- cache_table:save_ttl(key, ttl)
-- save for a given ttl
function cache_table.save_ttl(self, key, ttl, flag)
   local flag = flag or 0
   local serialized = self:serialize(self)

   self:set_internal('serialized_size', #serialized)
   if DEBUG then
      self:set_internal('serialized', serialized)
   end

   local shared_dict = self:get_shared_dict()

   return shared_dict:set(key, serialized, ttl, flag)
end

-- default serializer function
function cache_table.serialize(self, table)
   return pack(table)
end

function cache_table.deserialize(self, serialized)
   return unpack(serialized)
end


-- debug functions to turn off caching
local function _load_off(self, key)
   ngx_log(ngx_ERR,
           'Unable to load cache_table, check your lua_shared_dict conf.  ',
           debug.traceback())

   return self, false
end

local function _save_off(self, key)
   ngx_log(ngx_ERR,
           'Unable to save cache_table, check your lua_shared_dict conf.  ',
           debug.traceback())

   return self, false
end

-- copy cache_table
local cache_table_no_cache = {}

for k, v in pairs(cache_table) do
   cache_table_no_cache[k] = v
end

-- redirect all save, load function to dummy functions
cache_table_no_cache['load'] = _load_off
cache_table_no_cache['save_ttl'] = _save_off
cache_table_no_cache['save'] = _save_off
cache_table_no_cache['save_empty'] = _save_off


-- cache_table:new(ttl, shared_dict, [table], [opts])
--   shared_dict: a ngx.shared.DICT, declared in nginx.conf
--   ttl: caching time, in seconds.
--   table: pre-initalized table
function cache_table.new(self, ttl, shared_dict, table, opts)
   local opts = opts or {}
   if not opts.failed_ttl then
      -- opts.failed_ttl: caching time for ("empty entries"), default 10secs
      opts.failed_ttl = DEFAULT_FAILED_LOOKUP_CACHE_TTL
   end

   local cache_status = 'MISS'
   local __index = cache_table
   local err = nil

   if not shared_dict then
      ngx_log(ngx_ERR, 'Caching is disabled, check your lua_shared_dict conf. ',
              debug.traceback())

      -- not passing a valid ngx.shared.DICT turns off all the cache
      cache_status = 'DISABLED'
      __index = cache_table_no_cache
      err = 'Caching is disabled'
   end

   local mt = {
      __index = __index,
      __internal = {
         shared_dict = shared_dict,
         ttl = ttl,
         cache_status = cache_status,
         opts = opts,
      }
   }

   table = table or {}

   return setmetatable(table, mt), err
end


-- safety net
local class_mt = {
   __newindex = (
      function (table, key, val)
         error('Attempt to write to undeclared variable "' .. key .. '"')
      end),
}

setmetatable(cache_table, class_mt)

return cache_table
