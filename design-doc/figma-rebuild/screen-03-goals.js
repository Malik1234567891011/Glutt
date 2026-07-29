// use_figma script — screen 03 Goals (fileKey qYCBodrPLql8CrSNaafE9H) — ready to run verbatim
function hex(h){const n=parseInt(h.slice(1),16);return{r:((n>>16)&255)/255,g:((n>>8)&255)/255,b:(n&255)/255};}
await Promise.all([
  figma.loadFontAsync({family:"Bricolage Grotesque",style:"SemiBold"}),
  figma.loadFontAsync({family:"Nunito",style:"SemiBold"}),
]);
const styles = await figma.getLocalTextStylesAsync();
const S = n => styles.find(s=>s.name===n);
const creamVar = await figma.variables.getVariableByIdAsync("VariableID:3:3");

const f = figma.createFrame();
f.name = "03 Goals";
f.resize(390, 844); f.x = 1410; f.y = 0; f.clipsContent = true;
f.fills = [figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:1,g:1,b:1}},'color',creamVar)];

const sb = (await figma.getNodeByIdAsync("11:43")).createInstance();
f.appendChild(sb); sb.x = 0; sb.y = 0;

const track = figma.createRectangle();
track.name = "Progress Track";
track.resize(342, 8); track.cornerRadius = 100;
track.fills = [{type:'SOLID',color:{r:42/255,g:36/255,b:32/255},opacity:0.09}];
f.appendChild(track); track.x = 24; track.y = 60;
const pfill = figma.createRectangle();
pfill.name = "Progress Fill";
pfill.resize(114, 8); pfill.cornerRadius = 100;
pfill.fills = [{type:'SOLID',color:hex("#3E7A50")}];
f.appendChild(pfill); pfill.x = 24; pfill.y = 60;

const h1 = figma.createText();
h1.fontName = {family:"Bricolage Grotesque",style:"SemiBold"};
h1.characters = "Why do you want to cook more at home?";
await h1.setTextStyleIdAsync(S("Bricolage/H1 26").id);
h1.fills = [{type:'SOLID',color:hex("#241E19")}];
f.appendChild(h1);
h1.resize(300, 40);
h1.textAutoResize = "HEIGHT";
h1.textAlignHorizontal = "CENTER";
h1.x = 45; h1.y = 98;

const sub = figma.createText();
sub.fontName = {family:"Nunito",style:"SemiBold"};
sub.characters = "Pick anything that sounds like you";
await sub.setTextStyleIdAsync(S("Nunito/Subhead 14.5").id);
sub.fills = [{type:'SOLID',color:hex("#9A9082")}];
f.appendChild(sub);
sub.resize(280, 20);
sub.textAutoResize = "HEIGHT";
sub.textAlignHorizontal = "CENTER";
sub.x = 55; sub.y = 98 + h1.height + 8;

const goals = [
  ["Eat healthier without the fuss", true],
  ["Stop wasting food", false],
  ["Spend less on takeout", false],
  ["Cook with what I already have", true],
  ["Build a real cooking habit", false],
  ["Cook for people I love", false],
];
const selComp = await figma.getNodeByIdAsync("9:20");
const unselComp = await figma.getNodeByIdAsync("9:19");
let y = sub.y + sub.height + 20;
const rowIds = [];
for (const [label, selected] of goals) {
  const inst = (selected ? selComp : unselComp).createInstance();
  f.appendChild(inst);
  const key = Object.keys(inst.componentProperties).find(k=>k.startsWith("Label"));
  inst.setProperties({[key]: label});
  inst.x = 22; inst.y = y;
  y += inst.height + 11;
  rowIds.push(inst.id);
}

const cta = (await figma.getNodeByIdAsync("9:6")).createInstance();
f.appendChild(cta);
cta.resize(346, 60);
cta.x = 22; cta.y = 742;

return { createdNodeIds: [f.id], frameId: f.id, listBottom: y };
