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

local cache_table = { }

-- cache_table:new(ttl, shared_dict, [table], [opts])
--   shared_dict: a ngx.shared.DICT, declared in nginx.conf
--   ttl: caching time, in seconds.
--   table: pre-initalized table
function cache_table.new(self, ttl, shared_dict, table, opts)
   local err = nil

   local opts = opts or {}
   if not opts.failed_ttl then
      -- opts.failed_ttl: caching time for ("empty entries"), default 10secs
      opts.failed_ttl = DEFAULT_FAILED_LOOKUP_CACHE_TTL
   end

   local mt = {
      __index = cache_table,
      __internal = {
         shared_dict = shared_dict,
         ttl = ttl,
         cache_status = 'MISS',
         opts = opts,
      }
   }

   table = table or {}

   local res =  setmetatable(table, mt)

   -- not passing a ngx.shared.DICT turns off all the cache
   if not shared_dict then
      if DEBUG then
         ngx.log(ngx.CRIT, 'Caching is disabled. ', debug.traceback())
      end

      mt.__internal.cache_status = 'DISABLED'
      res.save = res._save_off
      res.load = res._load_off

      err = 'Caching is disabled'
   end

   return res, err
end

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
   local serialized = shared_dict:get(key)

   if serialized then

      if DEBUG then
         self:set_internal('serialized', serialized)
      end

      self:set_internal('serialized_size', #serialized)
      self:set_internal('cache_status', 'HIT')

      local mt = getmetatable(self)

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
function cache_table.save_empty(self, key)
   local opts = self:get_internal('opts')
   local ttl = opts.failed_ttl

   return self:save_ttl(key, ttl)
end

-- cache_table:save_ttl(key, ttl)
-- save for a given ttl
function cache_table.save_ttl(self, key, ttl)
   local serialized = self:serialize(self)

   self:set_internal('serialized_size', #serialized)
   if DEBUG then
      self:set_internal('serialized', serialized)
   end

   local shared_dict = self:get_shared_dict()

   return shared_dict:set(key, serialized, ttl)
end

-- default serializer function
function cache_table.serialize(self, table)
   return pack(table)
end

function cache_table.deserialize(self, serialized)
   return unpack(serialized)
end


-- debug functions to turn off caching
function cache_table._load_off(self, key)
   if DEBUG then
      self.internals = self:get_internal_table()
   end

   ngx.log(ngx.WARN, 'Unable to load object, check your configuration. ',
           debug.traceback())

   return self, false
end

function cache_table._save_off(self, key)
   if DEBUG then
      self.internals = self:get_internal_table()
   end

   ngx.log(ngx.WARN, 'Unable to save object, check your configuration. ',
           debug.traceback())

   return self, false
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
