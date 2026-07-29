// use_figma script — screen 08 Notifications soft-ask (fileKey qYCBodrPLql8CrSNaafE9H) — ready to run verbatim
function hex(h){const n=parseInt(h.slice(1),16);return{r:((n>>16)&255)/255,g:((n>>8)&255)/255,b:(n&255)/255};}
await Promise.all([
  figma.loadFontAsync({family:"Bricolage Grotesque",style:"SemiBold"}),
  figma.loadFontAsync({family:"Nunito",style:"SemiBold"}),
]);
const styles = await figma.getLocalTextStylesAsync();
const S = n => styles.find(s=>s.name===n);
const creamVar = await figma.variables.getVariableByIdAsync("VariableID:3:3");

const f = figma.createFrame();
f.name = "08 Notifications";
f.resize(390, 844); f.x = 3760; f.y = 0; f.clipsContent = true;
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
pfill.resize(304, 8); pfill.cornerRadius = 100;
pfill.fills = [{type:'SOLID',color:hex("#3E7A50")}];
f.appendChild(pfill); pfill.x = 24; pfill.y = 60;

const h1 = figma.createText();
h1.fontName = {family:"Bricolage Grotesque",style:"SemiBold"};
h1.characters = "Turn on gentle nudges";
await h1.setTextStyleIdAsync(S("Bricolage/H1 27").id);
h1.fills = [{type:'SOLID',color:hex("#241E19")}];
f.appendChild(h1);
h1.resize(280, 40);
h1.textAutoResize = "HEIGHT";
h1.textAlignHorizontal = "CENTER";
h1.x = 55; h1.y = 104;

const sub = figma.createText();
sub.fontName = {family:"Nunito",style:"SemiBold"};
sub.characters = "Cook on rhythm, never nagging";
await sub.setTextStyleIdAsync(S("Nunito/Subhead 14.5").id);
sub.fills = [{type:'SOLID',color:hex("#9A9082")}];
f.appendChild(sub);
sub.resize(280, 20);
sub.textAutoResize = "HEIGHT";
sub.textAlignHorizontal = "CENTER";
sub.x = 55; sub.y = 104 + h1.height + 8;

const cardComp = await figma.getNodeByIdAsync("11:25");
const cards = [
  { title: "Tonight's dinner is 20 minutes away", body: "You've got everything for Creamy Tomato Rigatoni.", time: "now" },
  { title: "Plan this week in 2 minutes", body: "Pick a few meals and Glutt builds your list.", time: "8:00 AM" },
  { title: "Use it before it turns", body: "Your spinach and mushrooms expire Sunday.", time: "Sun" },
];
const insts = [];
for (const c of cards) {
  const inst = cardComp.createInstance();
  f.appendChild(inst);
  const props = inst.componentProperties;
  const tKey = Object.keys(props).find(k=>k.startsWith("Title"));
  const bKey = Object.keys(props).find(k=>k.startsWith("Body"));
  const mKey = Object.keys(props).find(k=>k.startsWith("Time"));
  inst.setProperties({[tKey]: c.title, [bKey]: c.body, [mKey]: c.time});
  insts.push(inst);
}
const stackH = insts.reduce((a,i)=>a+i.height,0) + 12*2;
const topBound = sub.y + sub.height + 20;
let y = Math.round(topBound + (704 - 20 - topBound - stackH) / 2);
for (const inst of insts) { inst.x = 23; inst.y = y; y += inst.height + 12; }

const cta = (await figma.getNodeByIdAsync("9:6")).createInstance();
f.appendChild(cta);
const cKey = Object.keys(cta.componentProperties).find(k=>k.startsWith("Label"));
cta.setProperties({[cKey]: "Turn on notifications"});
cta.x = 24; cta.y = 704;

const link = (await figma.getNodeByIdAsync("9:10")).createInstance();
f.appendChild(link);
link.x = Math.round((390 - link.width) / 2); link.y = 780;

return { createdNodeIds: [f.id], frameId: f.id };
