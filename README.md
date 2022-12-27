# ANSI Terminal Writer

A custom pandoc writer for ANSI terminals.

> **Note**
>
> This writer requires features that are currently only in pandoc's
> development version. Use a nightly pandoc build to use this filter.

## Extensions

- **italic**: Render emphasized text using italics instead of underline;
  many terminal don't support italics, so this is disabled by default.

- **unicode**: Use Unicode characters, e.g. for footnote markers.

