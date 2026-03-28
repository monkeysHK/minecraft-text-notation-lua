# Minecraft Text Notation Parser for Lua

This is a parser for the [Minecraft Text Notation] that can be used on wikis of Minecraft servers. It is written in Teal and transpiled to Lua.

## Usage

To generate Wikitext from Minecraft Text Notation:

```lua
codegen.compile(Text, Options)
```

Text is a string written in Minecraft Text Notation.

Options is a table with the following fields:
- `useStrictMode`: whether to use strict mode (as defined in [Minecraft Text Notation]), default false

Output:

```
{
    kind = "CompileAccept",
    result = (string),
    warnings = (array of Problem)
}
or
{
    kind = "CompileFail",
    errors = (array of Problem)
}

where Problem is
{
    message = (string),
    position = {
        index = (integer),
        line = (integer),
        col = (integer)
    }
}
```

Warnings are problems that does not cause parsing to fail. For example, invalid escapes produce warnings when non-strict mode is used.

Errors are problems that cause parsing to fail. For example, unclosed tags produce errors when strict mode is used.

## Transpiling

The project is written in [Teal] and transpiled to Lua 5.1 to use with Scribunto.

[Teal] is required. Install Lua and LuaRocks, and then run:

```
luarocks install tl
```

Convert all tl files to lua:

```
tl gen *.tl --gen-compat off --gen-target 5.1
```

## Testing

Tests are run with [Busted]. By the convention of Busted, test files are located in the `spec/` folder and are named `*_spec.lua`.

[Busted] is required. Install Lua and LuaRocks, and then run:

```
luarocks install busted
```

Tests depends on the generated lua files, not the tl files. To run all tests, convert tl files to lua, and then run:

```
busted
```

[Minecraft Text Notation]: https://github.com/monkeyshk/minecraft-text-notation
[Teal]: https://teal-language.org/
[Busted]: https://github.com/lunarmodules/busted

