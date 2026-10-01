// Aroyn's original procedural field. No third-party renderer or component source.
// Copyright (c) 2026 vmsize. MIT; see the repository LICENSE.
export const fieldVariants = [
  {id:'geometry',label:'Геометрия',description:'Круги, квадраты и треугольники · ближе к прежнему фону',cell:10,glyphs:''},
  {id:'ascii',label:'ASCII · волны',description:'Точки, знаки и плотные символы · . : + * # @',cell:12,glyphs:'.:;+*#%@',waveDensity:2.2},
  {id:'lines',label:'ASCII · линии',description:'Сетка из штрихов, слешей и пересечений · / | — +',cell:12,glyphs:'-/|+\\='},
  {id:'binary',label:'Binary',description:'Спокойное поле из нулей и единиц · 0 1',cell:12,glyphs:'01'},
];
const smooth=value=>{const t=Math.max(0,Math.min(1,value));return t*t*(3-2*t);};
const fieldHash=(x,y)=>{const n=Math.sin(x*43.731+y*91.173)*19317.371;return n-Math.floor(n);};
function fieldNoise(x,y){
  const ix=Math.floor(x),iy=Math.floor(y),sx=smooth(x-ix),sy=smooth(y-iy);
  const top=fieldHash(ix,iy)*(1-sx)+fieldHash(ix+1,iy)*sx;
  const bottom=fieldHash(ix,iy+1)*(1-sx)+fieldHash(ix+1,iy+1)*sx;
  return top*(1-sy)+bottom*sy;
}
function evolvingNoise(x,y,time){
  const epoch=Math.floor(time),blend=smooth(time-epoch);
  return fieldNoise(x+epoch*37.7,y+epoch*19.3)*(1-blend)+fieldNoise(x+(epoch+1)*37.7,y+(epoch+1)*19.3)*blend;
}
const vertex=`#version 300 es
in vec2 position;
void main(){gl_Position=vec4(position,0.,1.);}`;
// Independent trigonometric interference, softly interpolated random regions,
// analytic geometric masks, and a locally generated system-font glyph atlas.
const fragment=`#version 300 es
precision highp float;
uniform vec2 resolution;
uniform float pixelRatio,cellSize,clockTime,reveal,brightness,glyphCount,waveDensity;
uniform int mode;
uniform sampler2D atlas;
out vec4 color;
float hash(vec2 p){return fract(sin(dot(p,vec2(43.731,91.173)))*19317.371);}
float grain(vec2 p){vec2 a=floor(p),b=fract(p);b=b*b*(3.-2.*b);return mix(mix(hash(a),hash(a+vec2(1.,0.)),b.x),mix(hash(a+vec2(0.,1.)),hash(a+1.),b.x),b.y);}
// Smoothly morph between independently seeded noise fields, rather than just
// translating one fixed pattern. Offsets and layers run at different rates.
float evolvingNoise(vec2 p,float t){float epoch=floor(t),blend=fract(t);blend=blend*blend*(3.-2.*blend);return mix(grain(p+epoch*vec2(37.7,19.3)),grain(p+(epoch+1.)*vec2(37.7,19.3)),blend);}
void main(){
 vec2 size=resolution/pixelRatio;
 vec2 p=vec2(gl_FragCoord.x,resolution.y-gl_FragCoord.y)/pixelRatio;
 vec2 cell=floor(p/cellSize),q=fract(p/cellSize),center=(cell+.5)*cellSize;
 float flow=clockTime*(mode==1?.7:.11);
 vec2 fieldPoint=center*waveDensity;
 if(mode==1){
  vec2 noisePoint=fieldPoint/230.;
  vec2 bend=vec2(evolvingNoise(noisePoint+vec2(flow*.09,-flow*.07),flow*.48),evolvingNoise(noisePoint+vec2(17.3,9.1)+vec2(-flow*.06,flow*.1),flow*.39+11.7));
  fieldPoint+=(bend-.5)*480.;
  fieldPoint+=vec2(sin(fieldPoint.y*.012+flow*1.1),cos(fieldPoint.x*.01-flow*.9))*38.;
 }
 float wave=sin(fieldPoint.x*.0048+fieldPoint.y*.0072+flow)
  +.62*sin(fieldPoint.x*.0081-fieldPoint.y*.0043-flow*.73)
  +.33*cos(length(fieldPoint-size*waveDensity*vec2(.3,.7))*.009-flow*.9);
 if(mode==1)wave+=.65*(evolvingNoise(fieldPoint/95.+vec2(-flow*.08,flow*.05),flow*.57+24.3)-.5)*2.
  +.28*sin(fieldPoint.x*.015-fieldPoint.y*.012-flow*1.3);
 float level=smoothstep(-1.05,1.4,wave+.48*(grain(center/90.)-.5));
 float edge=smoothstep(0.,.18,p.x/size.x)*smoothstep(0.,.18,1.-p.x/size.x)
  *smoothstep(0.,.18,p.y/size.y)*smoothstep(0.,.18,1.-p.y/size.y);
 float intro=smoothstep(-.1,.15,reveal*1.3-(p.x/size.x*.55+p.y/size.y*.45));
 float ink=0.;
 if(mode==0){
  vec2 d=abs(q-.5); float group=floor(grain(center/100.)*3.);
  float aa=1./(cellSize*pixelRatio);
  if(group<1.)ink=1.-smoothstep(.34-aa,.34+aa,max(d.x,d.y));
  else if(group<2.)ink=1.-smoothstep(.35-aa,.35+aa,length(q-.5));
  else {float triangle=max(abs(q.x-.5)*1.7-(q.y-.16),q.y-.81);ink=1.-smoothstep(-aa,aa,triangle);}
 }else{
  if(mode==1){
   float glyph=level*(glyphCount-1.),symbol=floor(glyph),next=min(symbol+1.,glyphCount-1.);
   float a=texture(atlas,vec2((symbol+q.x)/glyphCount,q.y)).a;
   float b=texture(atlas,vec2((next+q.x)/glyphCount,q.y)).a;
   ink=mix(a,b,smoothstep(.15,.85,fract(glyph)));
  }else ink=texture(atlas,vec2((floor(hash(cell)*glyphCount)+q.x)/glyphCount,q.y)).a;
 }
 float strength=(.16+.84*level)*edge*intro*brightness;
 vec3 background=vec3(.047,.055,.063);
 vec3 foreground=vec3(.31,.315,.32);
 color=vec4(mix(background,foreground,ink*strength),1.);
}`;

export function mountAroynField(root,{variant='geometry',paused=false,cellSize,brightness=.88,waveDensity,motionSpeed=1,introDuration=.8,forceCanvas=false}={}){
  const canvas=document.createElement('canvas');
  canvas.setAttribute('aria-hidden','true');
  Object.assign(canvas.style,{display:'block',width:'100%',height:'100%'});
  root.append(canvas);
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  let style=fieldVariants.find(v=>v.id===variant)||fieldVariants[0];
  let cell=cellSize||style.cell,light=brightness,density=waveDensity??style.waveDensity??1,speed=motionSpeed,userPaused=paused;
  let elapsed=Math.random()*100,introElapsed=0,last=performance.now(),frame=0,disposed=false,hidden=document.hidden;
  let width=1,height=1,dpr=1,draw;
  const gl=!forceCanvas&&canvas.getContext('webgl2',{alpha:false,antialias:false,depth:false,stencil:false,powerPreference:'low-power'});
  const resources=[];
  if(gl){
    const shader=(type,source)=>{const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error('Background shader compilation failed');resources.push(()=>gl.deleteShader(s));return s;};
    const program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,vertex));gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(program);
    if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error('Background shader linking failed');
    resources.push(()=>gl.deleteProgram(program));gl.useProgram(program);
    const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);resources.push(()=>gl.deleteBuffer(buffer));
    const location=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,2,gl.FLOAT,false,0,0);
    const uniforms=Object.fromEntries(['resolution','pixelRatio','cellSize','clockTime','reveal','brightness','glyphCount','waveDensity','mode','atlas'].map(n=>[n,gl.getUniformLocation(program,n)]));
    const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);resources.push(()=>gl.deleteTexture(texture));
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    let atlasGlyphs=null;
    draw=()=>{
      const glyphs=style.glyphs||'.';
      if(atlasGlyphs!==glyphs){
        const image=document.createElement('canvas');image.width=glyphs.length*32;image.height=32;
        const ctx=image.getContext('2d');ctx.fillStyle='white';ctx.font='25px ui-monospace, Consolas, monospace';ctx.textAlign='center';ctx.textBaseline='middle';
        [...glyphs].forEach((s,i)=>ctx.fillText(s,i*32+16,17));
        gl.bindTexture(gl.TEXTURE_2D,texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);atlasGlyphs=glyphs;
      }
      gl.viewport(0,0,canvas.width,canvas.height);gl.useProgram(program);
      gl.uniform2f(uniforms.resolution,canvas.width,canvas.height);gl.uniform1f(uniforms.pixelRatio,dpr);gl.uniform1f(uniforms.cellSize,cell);gl.uniform1f(uniforms.clockTime,elapsed);
      gl.uniform1f(uniforms.reveal,reduced.matches||introDuration===0?1:Math.min(1,introElapsed/introDuration));gl.uniform1f(uniforms.brightness,light);gl.uniform1f(uniforms.glyphCount,glyphs.length);gl.uniform1i(uniforms.mode,fieldVariants.indexOf(style));gl.uniform1i(uniforms.atlas,0);
      gl.uniform1f(uniforms.waveDensity,density);
      gl.drawArrays(gl.TRIANGLES,0,6);
    };
  }else{
    const ctx=canvas.getContext('2d',{alpha:false});
    if(!ctx){canvas.remove();return null;}
    // Separate simple fallback: the same cell scale and broad moving bands.
    draw=()=>{
      ctx.setTransform(dpr,0,0,dpr,0,0);ctx.fillStyle='#0c0e10';ctx.fillRect(0,0,width,height);
      ctx.font=`${cell*.8}px ui-monospace, Consolas, monospace`;ctx.textAlign='center';ctx.textBaseline='middle';
      for(let y=cell/2;y<height;y+=cell)for(let x=cell/2;x<width;x+=cell){
        const phase=elapsed*(style.id==='ascii'?.7:.11);
        let fieldX=x*density,fieldY=y*density;
        if(style.id==='ascii'){
          const nx=fieldX/230,ny=fieldY/230;
          fieldX+=(evolvingNoise(nx+phase*.09,ny-phase*.07,phase*.48)-.5)*480;
          fieldY+=(evolvingNoise(nx+17.3-phase*.06,ny+9.1+phase*.1,phase*.39+11.7)-.5)*480;
          const offsetX=Math.sin(fieldY*.012+phase*1.1)*38,offsetY=Math.cos(fieldX*.01-phase*.9)*38;fieldX+=offsetX;fieldY+=offsetY;
        }
        let wave=Math.sin(fieldX*.0048+fieldY*.0072+phase)+.62*Math.sin(fieldX*.0081-fieldY*.0043-phase*.73)+.33*Math.cos(Math.hypot(fieldX-width*density*.3,fieldY-height*density*.7)*.009-phase*.9);
        if(style.id==='ascii')wave+=.65*(evolvingNoise(fieldX/95-phase*.08,fieldY/95+phase*.05,phase*.57+24.3)-.5)*2+.28*Math.sin(fieldX*.015-fieldY*.012-phase*1.3);
        const value=Math.max(0,Math.min(1,(wave+1.95)/3.9));
        const edge=Math.min(1,x/(width*.18),(width-x)/(width*.18),y/(height*.18),(height-y)/(height*.18));
        const intro=reduced.matches||!introDuration?1:Math.max(0,Math.min(1,(introElapsed/introDuration*1.3-x/width*.55-y/height*.45+.1)/.25));
        const shade=Math.round(18+62*(.16+.84*value)*edge*intro*light);ctx.fillStyle=`rgb(${shade},${shade+1},${shade+2})`;
        if(style.id==='geometry'){
          const shape=Math.floor((Math.sin(x*.003-y*.005)+1)*1.49),r=cell*.34;
          if(shape===0)ctx.fillRect(x-r,y-r,r*2,r*2);
          else {ctx.beginPath();if(shape===1)ctx.arc(x,y,r,0,Math.PI*2);else{ctx.moveTo(x,y-r);ctx.lineTo(x+r,y+r);ctx.lineTo(x-r,y+r);ctx.closePath();}ctx.fill();}
        }else{const index=style.id==='ascii'?Math.min(style.glyphs.length-1,Math.floor(value*style.glyphs.length)):Math.floor(Math.abs(Math.sin(x*43.731+y*91.173))*19317.371)%style.glyphs.length;ctx.fillText(style.glyphs[index],x,y);}
      }
    };
  }
  const moving=()=>!userPaused&&!reduced.matches&&!hidden;
  function tick(now){
    frame=0;if(disposed)return;
    const dt=Math.min(.05,(now-last)/1000);last=now;
    if(moving()){elapsed+=dt*speed;introElapsed+=dt;}
    draw();if(moving())frame=requestAnimationFrame(tick);
  }
  function paint(){last=performance.now();if(!frame&&!disposed)frame=requestAnimationFrame(tick);}
  function resize(){const rect=root.getBoundingClientRect();width=Math.max(1,rect.width);height=Math.max(1,rect.height);dpr=Math.min(1.5,devicePixelRatio||1);canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);paint();}
  function visibility(){hidden=document.hidden;if(hidden){cancelAnimationFrame(frame);frame=0;}else paint();}
  function motionChange(){if(reduced.matches)introElapsed=introDuration;paint();}
  const observer=new ResizeObserver(resize);observer.observe(root);
  document.addEventListener('visibilitychange',visibility);reduced.addEventListener('change',motionChange);
  if(userPaused||reduced.matches)introElapsed=introDuration;
  resize();
  return{
    renderer:gl?'WebGL2':'Canvas2D',
    setVariant(id){const next=fieldVariants.find(v=>v.id===id);if(!next)return;style=next;cell=next.cell;density=next.waveDensity??1;paint();},
    setCellSize(value){cell=Math.max(7,Math.min(22,Number(value)||10));paint();},
    setWaveDensity(value){density=Math.max(1,Math.min(3.5,Number(value)||1));paint();},
    setMotionSpeed(value){speed=Math.max(.25,Math.min(2.5,Number(value)||1));paint();},
    setBrightness(value){light=Math.max(.25,Math.min(1.6,Number(value)||.88));paint();},
    setPaused(value){userPaused=Boolean(value);if(userPaused){cancelAnimationFrame(frame);frame=0;}paint();},
    replay(){introElapsed=userPaused||reduced.matches?introDuration:0;paint();},
    destroy(){disposed=true;cancelAnimationFrame(frame);observer.disconnect();document.removeEventListener('visibilitychange',visibility);reduced.removeEventListener('change',motionChange);resources.forEach(release=>release());canvas.remove();},
  };
}
