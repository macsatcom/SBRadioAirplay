"""Shared helpers: load applet Lua modules into a Lua 5.1 runtime (lupa),
with Jive's module() convention and injectable fake modules."""
from pathlib import Path

import pytest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
APPLET = ROOT / "applet" / "AirPlay"


class Lua:
    def __init__(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        # minimal loop.simple: oo.class(M[, Base]) makes M callable -> new instance
        self.rt.execute(r'''
          package.loaded['loop.simple'] = {class=function(M, Base)
            setmetatable(M, {__index=Base, __call=function(cls, ...)
              local o = setmetatable({}, {__index=cls}); return o end})
            return M
          end}
        ''')

    def fake(self, name, lua_expr):
        """package.loaded[name] = <lua_expr>"""
        self.rt.execute(f"package.loaded[{name!r}] = {lua_expr}")

    def load(self, module):
        """Load applets.AirPlay.<module> from the applet directory."""
        name = f"applets.AirPlay.{module}"
        src = (APPLET / f"{module}.lua").read_text()
        fn = self.rt.execute(
            "return function(src, name) local f = assert(loadstring(src, '@' .. name)); "
            "local m = f(name); package.loaded[name] = package.loaded[name] or m; "
            "return package.loaded[name] end")
        return fn(src, name)

    def __call__(self, code):
        return self.rt.execute(code)

    def eval(self, code):
        return self.rt.eval(code)


@pytest.fixture
def lua():
    return Lua()


def lua_table(lua, d):
    t = lua.eval("{}")
    for k, v in d.items():
        t[k] = v
    return t
