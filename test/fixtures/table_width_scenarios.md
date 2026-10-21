# Table width scenarios

Check Reading and Live Preview at 320, 540 and 900 logical pixels, with 1× and 2× text scaling and both LTR and RTL directions. Resize without editing: Markdown source must stay unchanged.

## 1. Short tables stay compact

| ID | OK |
| --- | --- |
| A1 | Yes |
| B2 | No |

The table should not stretch across a wide page.

## 2. Short IDs, long descriptions, right-aligned numbers

| ID | Description | Amount |
| :--- | :--- | ---: |
| A1 | A longer explanation should receive the available space while short identifiers and numeric values remain compact and easy to scan. | 123.45 |
| B2 | Brief note. | 7 |
| C3 | Another description that wraps naturally without overlapping the following row. | 1024.00 |

## 3. Headers longer than their body cells

| Expected completion date and delivery window | ID |
| --- | --- |
| Soon | A |
| TBD | B |

The long header must influence the width, and all of its lines must fit in the header row.

## 4. Chinese and English content

| 编号 | Description / 说明 | 状态 |
| :--- | :--- | :---: |
| A1 | 中文说明与 English mixed content：窄屏下应完整换行，保留短编号列，并确保下一行不会覆盖当前说明。 | 完成 |
| B2 | Next step：继续检查中英文混排，以及字体放大后的行高。 | 待办 |

## 5. URLs, code fonts and file chips

| Kind | Content |
| --- | --- |
| URL | <https://example.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa> |
| Code | `iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii` |
| File | [report.pdf](report.pdf) |
| Link | [Doc](https://example.com/a/very/long/destination/that/must/not/determine/the/visible/column/width) |

Long tokens should wrap within their row. The code should fit on one line when its actual font fits the available width. With file-link chips enabled, a short file label should not ellipsize because icon or padding space was omitted.

## 6. Many columns on a narrow viewport

| ID | When | Owner | State | Value | Notes |
| :--- | :--- | :--- | :--- | ---: | :--- |
| Identifier with readable context | Scheduled delivery window | Responsible person and team | Current progress and next step | 12345678901234567890 | Final column with useful details |
| A2 | Next week | Platform team | In progress | 42 | Last-column editing remains reachable |

At 320px, scroll to the last column in both directions. In Live Preview, use Tab and Shift+Tab across all cells: the focused cell should become visible, including at 4× text scale with the editor's default padding. Touch-drag a visible column handle: reordering must not also scroll the table.
