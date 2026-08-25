# Editor Regression Checklist

Run the automated test suite before every editor release. Then verify this checklist in the built app using an empty note and a populated note.

## Editor Layout Invariant

- A logical line's geometry comes from its structured line kind and the available width, never from the current caret, selection, focus, or typing attributes.
- Empty terminal structured lines must use the same layout path and metrics as their populated form. They must not rely on AppKit's default extra-line-fragment styling.
- Marker overlays, caret placement, hit testing, scrolling, and document height must all read the same canonical text layout geometry.

## Plain Text

- Type, insert, replace, and delete at the beginning, middle, and end of every line.
- Click empty space after text and confirm the caret moves to that line's end.
- Drag-select forward and backward across the first, middle, and final lines.
- Copy, cut, paste, undo, and redo single-line and multi-line selections.
- Press Tab with a caret and with a partial or multi-line selection; confirm the original selection remains selected.

## Structured Lines

- Create task, bullet, numbered, quote, divider, table, and code-block lines through raw Markdown and the slash menu.
- Press Return, Shift-Return, Tab, Shift-Tab, Backspace, and Delete at every nesting level.
- With only a caret in a task, bullet, or numbered item, confirm Tab and Shift-Tab move the marker and text together between hierarchy levels without inserting spaces into the content.
- With only a caret in plain text, confirm Tab inserts indentation at the caret instead of moving the entire line.
- Confirm markers, text, caret, checked state, and indentation stay aligned after editing and undo/redo.
- Delete or insert a middle numbered item and confirm following numbers update at the same level only.
- Copy and cut complete structured lines; paste them into another day and confirm their Markdown structure survives.

## Code Blocks

- Create empty and populated blocks at the first line, middle, and end of the note.
- Place an empty final block after a populated block and several blank lines; confirm its initial height matches its height after the first character.
- Move the caret between a terminal empty block and lines above it; confirm the block does not move or resize.
- Confirm the border and text do not move when the first character is typed.
- Confirm normal lines above, below, and between blocks have visible spacing and remain clickable/selectable.
- Create multiline and wrapped code, then click and drag-select every line after the block.
- With the note scrolled, split a 10-line terminal code block at an interior line using `/` -> Numbered list; after the menu closes, click the numbered line and every line in the lower code block.
- Change the language and confirm highlighting and the Markdown fence both update.
- Hover the language chip and confirm it uses the pointing-hand cursor; code text outside the chip must keep the I-beam cursor.
- Copy one complete block and multiple blocks; confirm opening fence, language, content, and closing fence are present.
- Copy a partial word inside code and confirm only the selected text is copied.

## Lists And Tasks

- Verify top-level and nested markers, caret positions, wrapping, hover cursor, and checkbox click targets.
- Confirm wrapped text does not block checkbox clicks on following lines.
- Paste tasks into blank lines and between existing tasks; confirm each marker stays attached to its text.
- Select only task text and delete it; confirm the checkbox remains.

## Images, Tables, And Search

- Paste, resize, select, copy, delete, undo, and redo images; reopen the note and confirm following text does not overlap.
- Select OCR text at character granularity and copy it; separately select and copy the whole image.
- Edit and render tables; verify wrapping, inline Markdown, row borders, caret access, and selection.
- Verify Find in Note and Go To across plain text, lists, tables, code, and OCR text, including scrolling to every match.

## Semantic Note Zoom

- Verify `Cmd-Plus`, `Cmd-Minus`, `Cmd-0`, and trackpad pinch at 60%, 100%, and 200%.
- Confirm zoom changes note content only. The window frame, header controls, and editor width must not scale.
- Confirm wrapped plain text reflows vertically without adding a horizontal scrollbar.
- Verify task checkboxes, bullets, numbered prefixes, quote rails, code blocks, language chips, dividers, table cells, image previews, image resize handles, OCR regions, selection highlights, and carets all scale together.
- At every zoom level, click checkboxes, code-language chips, list text, and lines before and after structured blocks; confirm hit targets and cursors remain aligned.
- Resize an image while zoomed, return to 100%, and confirm its saved logical width has not been multiplied by the note zoom.
- Zoom a long scrolled note and confirm the same reading region remains visible instead of jumping to the top.
- Change zoom while composing with an IME and confirm composition is preserved and the pending zoom applies afterward.
- Restart the app and confirm the saved zoom level is restored. Open legacy settings without a zoom value and confirm they default to 100%.
- Confirm the source Markdown and stored note data are unchanged by zooming.

## Window And Themes

- Resize from every edge and corner at minimum and large window sizes; confirm the window never moves or trembles.
- Check header controls, cursors, selection, switches, buttons, and scrollbars in Yellow, Light, and Dark themes, both focused and unfocused.
- Restart the app and confirm editor layout, images, selection targets, window size, and local/iCloud content remain correct.
