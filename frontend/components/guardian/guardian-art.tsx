import { useId } from 'react';

const shell = 'M150 43 Q156 41 163 44 L219 62 Q234 67 234 83 L231 120 C227 156 204 182 166 201 Q156 207 146 201 C108 182 85 156 81 120 L78 83 Q78 67 94 62 Z';

export function GuardianArt() {
  const id = useId();
  return <svg className="guardian-art" viewBox="0 0 312 249" aria-hidden="true" focusable="false">
    <defs>
      <linearGradient id={id + 'rim'} x2="0.75" y2="1">
        <stop stopColor="#d8efa0"/><stop offset=".38" stopColor="#8cab65"/><stop offset=".73" stopColor="#354e36"/><stop offset="1" stopColor="#73905d"/>
      </linearGradient>
      <linearGradient id={id + 'shell'} x2=".75" y2="1">
        <stop stopColor="#91a96f"/><stop offset=".28" stopColor="#4b6544"/><stop offset=".63" stopColor="#263d2e"/><stop offset="1" stopColor="#435e3e"/>
      </linearGradient>
      <linearGradient id={id + 'glass'} x2="0" y2="1">
        <stop stopColor="#101b16"/><stop offset="1" stopColor="#192a22"/>
      </linearGradient>
      <radialGradient id={id + 'shadow'}>
        <stop stopColor="#070b08" stopOpacity=".92"/><stop offset="1" stopColor="#070b08" stopOpacity="0"/>
      </radialGradient>
      <radialGradient id={id + 'core'}>
        <stop stopColor="#d3fa79" stopOpacity=".35"/><stop offset="1" stopColor="#d3fa79" stopOpacity="0"/>
      </radialGradient>
    </defs>
    <ellipse cx="156" cy="132" rx="137" ry="67" transform="rotate(-19 156 132)" fill="none" stroke="#567054" strokeOpacity=".58" strokeDasharray="2 5"/>
    <ellipse cx="156" cy="132" rx="134" ry="67" transform="rotate(19 156 132)" fill="none" stroke="#405742" strokeOpacity=".52"/>
    <ellipse className="guardian-shadow" cx="156" cy="219" rx="77" ry="14" fill={`url(#${id}shadow)`}/>
    <path className="guardian-field" d={shell} fill="#d3fa79" fillOpacity=".08" stroke="#d3fa79" strokeWidth="1.5"/>
    <g className="guardian-float">
      <g className="guardian-tilt">
        <g className="guardian-response">
          <path d={shell} transform="translate(0 5)" fill="#1b2a20" stroke="#4e6847" strokeWidth="2"/>
          <path d={shell} fill={`url(#${id}shell)`} stroke={`url(#${id}rim)`} strokeWidth="2.5"/>
          <path d="M87 90v-7q0-10 11-13l53-18q5-2 10 0l53 17q11 4 12 14v7M92 130c8 27 27 46 57 62q7 4 14 0c29-16 48-35 57-62" fill="none" stroke="#d3efa1" strokeOpacity=".32" strokeLinecap="round"/>
          <path d="M97 98q0-9 9-12l44-13q6-2 12 0l44 13q9 3 9 12l-3 27q-1 9-10 12l-40 10q-6 2-12 0l-40-10q-9-3-10-12Z" fill={`url(#${id}glass)`} stroke="#79916c" strokeWidth="1.4"/>
          <path d="m108 97 42-12q6-2 12 0l42 12" fill="none" stroke="#364d3b" strokeLinecap="round"/>
          <g className="guardian-gaze">
            <g className="guardian-eyes">
              <rect x="125" y="105" width="9" height="15" rx="4.5" fill="#dcff99"/>
              <rect x="178" y="105" width="9" height="15" rx="4.5" fill="#dcff99"/>
            </g>
          </g>
          <path d="m109 147 18 13m76-13-18 13" fill="none" stroke="#718e60" strokeLinecap="round" strokeDasharray="8 4"/>
          <g className="guardian-core">
            <circle cx="156" cy="169" r="29" fill={`url(#${id}core)`}/>
            <path d="m156 157 12 12-12 12-12-12Z" fill="#182b20" stroke="#9fbe72"/>
            <path d="m156 162 7 7-7 7-7-7Z" fill="#d3fa79"/>
            <path d="m156 166 3 3-3 3-3-3Z" fill="#f2ffd7"/>
          </g>
        </g>
      </g>
    </g>
    <g className="guardian-node" data-node="unichain" transform="translate(38 110)" style={{ color: '#f7a6d3' }}>
      <NodeRing/><path d="M-4-4v8h8" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
    </g>
    <g className="guardian-node" data-node="reactive" transform="translate(257 57)" style={{ color: '#76dec3' }}>
      <NodeRing/><path d="m-6 1 3-4 4 6 4-4" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </g>
    <g className="guardian-node" data-node="base" transform="translate(277 158)" style={{ color: '#8aabff' }}>
      <NodeRing/><path d="M-5 0h10" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
    </g>
  </svg>;
}

function NodeRing() {
  return <><circle className="guardian-node-halo" r="23" fill="currentColor"/><circle r="13" fill="#152219" stroke="currentColor" strokeOpacity=".8"/></>;
}
