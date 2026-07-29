// use_figma script — screen 05 In 4 Weeks (fileKey qYCBodrPLql8CrSNaafE9H) — ready to run verbatim
function hex(h){const n=parseInt(h.slice(1),16);return{r:((n>>16)&255)/255,g:((n>>8)&255)/255,b:(n&255)/255};}
await Promise.all([
  figma.loadFontAsync({family:"Bricolage Grotesque",style:"SemiBold"}),
  figma.loadFontAsync({family:"Nunito",style:"SemiBold"}),
]);
const styles = await figma.getLocalTextStylesAsync();
const S = n => styles.find(s=>s.name===n);
const creamVar = await figma.variables.getVariableByIdAsync("VariableID:3:3");

const f = figma.createFrame();
f.name = "05 In 4 Weeks";
f.resize(390, 844); f.x = 2350; f.y = 0; f.clipsContent = true;
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
pfill.resize(190, 8); pfill.cornerRadius = 100;
pfill.fills = [{type:'SOLID',color:hex("#3E7A50")}];
f.appendChild(pfill); pfill.x = 24; pfill.y = 60;

const h1 = figma.createText();
h1.fontName = {family:"Bricolage Grotesque",style:"SemiBold"};
h1.characters = "Here's where you'll be\nin 4 weeks";
await h1.setTextStyleIdAsync(S("Bricolage/H1 27").id);
h1.fills = [{type:'SOLID',color:hex("#241E19")}];
f.appendChild(h1);
h1.resize(290, 40);
h1.textAutoResize = "HEIGHT";
h1.textAlignHorizontal = "CENTER";
h1.x = 50; h1.y = 104;

const cardComp = await figma.getNodeByIdAsync("11:14");
const cards = [
  { title: "Cook with confidence", body: "Hands-free guided recipes that actually work", icon: "7:34", g0: "#F4906F", g1: "#D9483B", glow: "#E1523D" },
  { title: "A kitchen that runs itself", body: "Your pantry, tools, and grocery list in one place", icon: "7:37", g0: "#6FB183", g1: "#2E5339", glow: "#2E5339" },
  { title: "Less waste, less takeout", body: "Use what you have before it goes off", icon: "7:7", g0: "#F3C877", g1: "#D99A3C", glow: "#D99A3C" },
];
const insts = [];
for (const c of cards) {
  const inst = cardComp.createInstance();
  f.appendChild(inst);
  const props = inst.componentProperties;
  const tKey = Object.keys(props).find(k=>k.startsWith("Title"));
  const bKey = Object.keys(props).find(k=>k.startsWith("Body"));
  const iKey = Object.keys(props).find(k=>k.startsWith("Icon"));
  inst.setProperties({[tKey]: c.title, [bKey]: c.body, [iKey]: c.icon});
  const sq = inst.findOne(n=>n.name==="Icon Square");
  sq.fills = [{type:"GRADIENT_LINEAR",gradientTransform:[[0.5,0.5,0],[-0.5,0.5,0.5]],gradientStops:[
    {position:0,color:{...hex(c.g0),a:1}},{position:1,color:{...hex(c.g1),a:1}}]}];
  sq.effects = [{type:"DROP_SHADOW",color:{...hex(c.glow),a:0.45},offset:{x:0,y:10},radius:10,visible:true,blendMode:"NORMAL"}];
  const glow = inst.findOne(n=>n.name==="Glow");
  glow.fills = [{type:"GRADIENT_RADIAL",gradientTransform:[[1,0,0],[0,1,0]],gradientStops:[
    {position:0,color:{...hex(c.glow),a:0.55}},{position:1,color:{...hex(c.glow),a:0}}]}];
  const iconInst = inst.findOne(n=>n.type==="INSTANCE" && n.parent.name==="Icon Square");
  if (iconInst) iconInst.findAll(n=>n.type==="VECTOR").forEach(v=>{ v.fills = [{type:'SOLID',color:{r:1,g:1,b:1}}]; });
  insts.push(inst);
}
const stackH = insts.reduce((a,i)=>a+i.height,0) + 14*2;
const topBound = 104 + h1.height + 20;
let y = Math.round(topBound + (726 - topBound - stackH) / 2);
for (const inst of insts) { inst.x = 24; inst.y = y; y += inst.height + 14; }

const cta = (await figma.getNodeByIdAsync("9:6")).createInstance();
f.appendChild(cta); cta.x = 24; cta.y = 740;

return { createdNodeIds: [f.id], frameId: f.id, cardHeights: insts.map(i=>i.height) };
