# 更多 Markdown 细节

中文 English 😀 é，转义 \*不是斜体\*，HTML 实体 &amp; &lt;。第一行软换行
第二行软换行。

## 二级标题
### 三级标题
#### 四级标题
##### 五级标题
###### 六级标题

---

普通内容。%%隐藏注释%% ^audit-block

## HTML 子集

<details><summary>展开详细说明</summary>

这是可折叠内容，包含 **Markdown 强调**。

</details>

<div align="center">居中内容</div>

<input type="text" placeholder="本地表单输入" value="初始值">

<input type="checkbox" checked>

<progress value="60" max="100"></progress>

<kbd>Command</kbd> + <kbd>B</kbd>，H<sub>2</sub>O 和 x<sup>2</sup>。

## 引用与代码边界

> 第一层引用
>> 第二层引用

```unknown
**literal** [link](https://example.com) <script>not executed</script>
```

![本地图片|100](sample.png)

## 链接与脚注

[同文标题](#html-子集) / [本地文档](Second.md) / [[Second]] / ![[Second]]

脚注第一次[^same] 和第二次[^same]，以及 ^[行内脚注]。

[^same]: 共享脚注正文。

## 错误回退

未闭合的 `inline code 和 **粗体按字面处理。

$\notARealCommand{x}$

> [!unknown] 未知 Callout
> 应有可见回退内容。
