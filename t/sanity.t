# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket no_plan;
use Cwd qw(cwd);

repeat_each(2);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path    "$pwd/?.lua;;";
    lua_shared_dict     cache     1M;
};

no_long_string();

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig

--- config

    location /clear {
        content_by_lua '
            ngx.shared.cache:flush_all()

            ngx.say("clear")
        ';
    }

    location /t {
        content_by_lua '
            local cache_table = require("cache_table")

            local cached_lookups = 0

            for i = 1, 2 do

                local cache_table = cache_table:new(60, ngx.shared.cache)

                local cache_table, cached = cache_table:load("KEY")

                if not cached then

                    cache_table.val = "bar"
                    cache_table.flags = 0
                    cache_table.test = true

                    cache_table:save("KEY")
                else
                    cached_lookups = cached_lookups + 1
                end

                ngx.say("val: ", cache_table.val, ", ",
                        "flags: ", cache_table.flags, ", ",
                        "test: ", cache_table.test)

            end

            ngx.say("cached lookups: ", cached_lookups)
        ';
    }
--- request eval
[ "GET /clear",
  "GET /t",
  "GET /t"
]
--- response_body eval
[
"clear
",
"val: bar, flags: 0, test: true
val: bar, flags: 0, test: true
cached lookups: 1
",
"val: bar, flags: 0, test: true
val: bar, flags: 0, test: true
cached lookups: 2
"
]
--- no_error_log
[error]
