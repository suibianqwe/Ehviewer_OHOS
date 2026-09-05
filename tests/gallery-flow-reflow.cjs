// assembleApp 后运行：node tests/gallery-flow-reflow.cjs <TypeScript模块路径> [编译后的GalleryScenes.ts]
// 检查 WaterFlow 使用整体顶部避让，不把避让高度加入卡片行间距。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const file = process.argv[3] || path.resolve(__dirname,
  '../entry/build/default/cache/default/default@CompileArkTS/esmodule/release/entry/src/main/ets/components/GalleryScenes.ts');
const source = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
let method;
function find(node) {
  if (ts.isMethodDeclaration(node) && node.name.getText(source) === 'galleryFlowItem') method = node;
  ts.forEachChild(node, find);
}
find(source);
assert.ok(method, '必须先编译 HAP 生成画廊布局代码');
const sourceText = fs.readFileSync(file, 'utf8');
assert.match(sourceText, /\.padding\(\{[\s\S]*top:\s*this\.expandedTitleContentInset\(\)/,
  'WaterFlow 必须使用整体顶部 padding');
assert.doesNotMatch(sourceText, /\.margin\(\{\s*top:\s*index\s*<\s*this\.galleryColumnCount\(\)/,
  'FlowItem 不得按首行增加顶部 margin');
console.log('瀑布流回归通过：避让高度位于 WaterFlow 顶部，列数变化不会放大行间距');
