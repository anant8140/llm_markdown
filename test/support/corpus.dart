/// Markdown documents shaped like AI chat answers, used to check that
/// streaming gives the same result as parsing the whole text at once.
const Map<String, String> corpus = {
  'answer with headings, lists and code': '''
# Setting up the project

Follow these **three steps** to get started. Each one takes a *minute* or less.

## 1. Install

Run the command below:

```bash
flutter pub add llm_markdown

# then fetch packages
flutter pub get
```

## 2. Use it

- Create a `StreamingMarkdownController`
- Pass it to the widget
  - nested detail with a [link](https://example.com)
- Call `append` for each chunk

1. First
2. Second

3. Third, after a blank line

Done. ~~Old way~~ new way.
''',
  'loose list with paragraphs and code inside items': '''
Here is what changed:

1. **Parser**: the parser now reads only the new text.

   It keeps finished blocks.

2. **Renderer**: blocks are cached.

   ```dart
   final widget = StreamingMarkdown(controller: controller);
   ```

3. **Tests** were added.

That is all.
''',
  'table, quote and rule': '''
| Package | Downloads | Likes |
| :--- | ---: | :---: |
| alpha | 1,200 | 30 |
| beta | 980 | 12 |

> **Note**
> Numbers are from the last 30 days.
>
> - first point
> - second point

---

Final paragraph with `inline code` and a line
that wraps onto a second line.
''',
  'fences of every shape': '''
Text right before a fence
```python
def f():

    return 1
```
Text right after a fence

~~~~
a tilde fence with ``` inside
~~~~

````md
```dart
nested fence
```
````

```
unclosed at the end of the document
''',
  'setext headings, indented code and html': '''
Title in setext style
=====================

Subtitle
--------

    indented code line 1

    indented code line 2

<!-- a comment

that spans a blank line -->

<div>
html block
</div>

after html
''',
  'task lists, unicode and emoji': '''
## આજનું કામ 🚀

- [x] નમસ્તે દુનિયા
- [ ] **બોલ્ડ** અને _ઇટાલિક_
- [ ] emoji 👨‍👩‍👧‍👦 family

Paragraph with a hard break
on the next line, and an autolink https://dart.dev.
''',
  'paragraph interrupted by blocks': '''
Some text
# A heading right after text
More text
- a list right after text
- second item
Lazy text after the list
> a quote right after text
continued lazily

* * *
- after a thematic break
''',
  'lines that only look like a heading or a fence': '''
Some text
#hashtag is not a heading, so this stays one paragraph
```inline code``` at the start of a line is not a fence
and the paragraph goes on.

#
''',
  'html block holding a heading': '''
<div>
# not a heading, still html
</div>
After the html.
''',
  'non-breaking space is not a blank line':
      'First line\n\u00a0\nstill the same paragraph\n\nNext paragraph\n',
  'list ends with unindented text after blank line': '''
- one
- two

Plain paragraph after the list.

- three

    four is indented code-like inside the list

Back to the top level.
''',
};
