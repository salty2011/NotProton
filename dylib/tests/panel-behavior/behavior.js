// What the panel renders, checked against both forms of the one payload.
'use strict';
const { panel, walk, details, runner, FORMS } = require('./harness');

const emit = process.argv[2];
if (!emit) { console.error('usage: behavior.js <emit>'); process.exit(2); }

let failed = 0;
for (const form of Object.keys(FORMS)) {
  const { render: P, written } = panel(emit, form);
  const t = runner(form);
  const nodes = opts => walk(P({ details: details(opts + ' %command%') }));
  const toggles = ns => ns.filter(x => x.type === 'Toggle').map(x => x.props.label);
  const sections = ns => ns.filter(x => x.type === 'Section').map(x => x.props.label.split(' ')[0]);
  const last = () => (written.length ? written[written.length - 1].opts : '');

  t.ok(P({ details: details('', { vecPlatforms: ['osx'], strCompatToolName: '' }) }) === null,
       'a mac build with nothing pinned renders no panel');
  t.ok(P({ details: details('', { unAppID: 3420702832, vecPlatforms: ['osx'],
                                  strCompatToolName: '' }) }) !== null,
       'a shortcut renders the panel before a tool name reaches the page');

  let r = nodes('');
  t.ok(toggles(r).length === 6 && sections(r).length === 3, 'automatic shows six toggles in three sections');
  t.ok(r.filter(x => x.type === 'Dropdown').length === 2, 'two dropdowns');
  t.ok(!('label' in r.find(x => x.type === 'Dropdown').props), 'the backend dropdown carries no label column');

  r = nodes('CX_GRAPHICS_BACKEND=dxmt');
  t.ok(toggles(r).filter(l => l === 'DLSS').length === 1 && sections(r).includes('MetalFX'),
       'dxmt keeps one DLSS and keeps MetalFX');
  r = nodes('CX_GRAPHICS_BACKEND=d3dmetal');
  t.ok(toggles(r).filter(l => l === 'DLSS').length === 1 && !sections(r).includes('MetalFX'),
       'd3dmetal keeps one DLSS and hides MetalFX');
  // Both flags are labeled DLSS, so a backend showing its own and its neighbor's
  // would put the same word on two rows.
  for (const b of ['', 'd3dmetal', 'dxmt', 'dxvk', 'wined3d']) {
    const ls = toggles(nodes(b ? 'CX_GRAPHICS_BACKEND=' + b : ''));
    t.ok(ls.filter(l => l === 'DLSS').length === (b === 'dxvk' || b === 'wined3d' ? 0 : 1),
         `${b || 'automatic'} shows DLSS at most once (${ls.join(',')})`);
  }
  // The row that writes the flag the chosen backend actually reads.
  const dlss = (b, key) => {
    written.length = 0;
    nodes('CX_GRAPHICS_BACKEND=' + b).find(x => x.props.label === 'DLSS').props.onChange(true);
    t.ok(last().includes(key + '=1'), `${b} DLSS writes ${key} (${last()})`);
  };
  dlss('d3dmetal', 'D3DM_ENABLE_METALFX');
  dlss('dxmt', 'DXMT_ENABLE_NVEXT');
  t.ok(nodes('CX_GRAPHICS_BACKEND=dxmt DXMT_ENABLE_NVEXT=1')
         .find(x => x.props.label === 'DLSS').props.checked === true,
       'the dxmt DLSS toggle reads as on from its argument');

  t.ok(nodes('CX_GRAPHICS_BACKEND=dxmt').find(x => x.type === 'Dropdown').props.selectedOption === 'dxmt',
       'the backend dropdown reflects the current value');
  t.ok(nodes('MTL_HUD_ENABLED=1').find(x => x.props.label === 'Metal HUD').props.checked === true,
       'a toggle reads as on from its argument');

  nodes('CX_GRAPHICS_BACKEND=dxmt').filter(x => x.type === 'Dropdown')[1].props.onChange({ data: '2.0' });
  t.ok(last().includes('metalSpatialUpscaleFactor=2.0'), 'the upscaler writes its factor');

  // The section names the factor, so a label promising a resolution to go and set in
  // the game is the wording this replaced.
  const upscaler = nodes('CX_GRAPHICS_BACKEND=dxmt').find(x => x.type === 'Section' &&
    x.props.label.indexOf('MetalFX') === 0);
  t.ok(/Samples from the resolution the game is set to/.test(upscaler.props.label),
       'the upscaler section says where it samples from');
  const factors = nodes('CX_GRAPHICS_BACKEND=dxmt').filter(x => x.type === 'Dropdown')[1]
    .props.rgOptions.map(o => o.label);
  t.ok(factors.join(',') === 'Off,1.5x,1.72x,2x,3x', `the factors name themselves (${factors.join(',')})`);

  // The value is the name wine gives the library, which is lower case, and the label is
  // the name in a list of four the reader picks from.
  const backends = nodes('').find(x => x.type === 'Dropdown').props.rgOptions;
  t.ok(backends.map(o => o.label).join(',') === 'Automatic,D3DMetal,DXMT,DXVK,WineD3D',
       `the backends name themselves (${backends.map(o => o.label).join(',')})`);
  t.ok(backends.map(o => o.data).join(',') === ',d3dmetal,dxmt,dxvk,wined3d',
       'the backend values stay as the tool reads them');

  const root = P({ details: details('') });
  t.ok(root.props.className === 'MSCXPanel', 'the panel root carries its own class');
  const classes = nodes('').filter(x => x.type === 'Toggle').map(x => x.props.className);
  t.ok(classes.length === 6 && classes.every(c => c === 'MSCXRow'), 'every checkbox carries the row class');
  const raw = o => nodes(o).find(x => x.props.label === 'Let games read controllers directly');
  t.ok(sections(nodes('')).includes('Controllers') && raw('').props.checked === false,
       'controller hiding is on unless the game says otherwise');
  t.ok(nodes('').some(x => x.type === 'Section' && x.props.label === 'Controllers (May break Steam Input. Not recommended)'),
       'the controller section warns what the row changes');
  written.length = 0;
  raw('').props.onChange(true);
  t.ok(last().trim() === 'NOTPROTON_RAW_CONTROLLERS=1 %command%', `the controller row writes its flag (${last()})`);
  t.ok(raw('NOTPROTON_RAW_CONTROLLERS=1').props.checked === true, 'the controller row reads its flag');
  written.length = 0;
  raw('NOTPROTON_RAW_CONTROLLERS=1 WINEMSYNC=1').props.onChange(false);
  t.ok(last().trim() === 'WINEMSYNC=1 %command%', `turning the controller row off removes its flag (${last()})`);
  const css = nodes('').filter(x => x.type === 'style');
  t.ok(css.length === 1 && css[0].props.children.includes('.MSCXPanel .MSCXRow{'),
       'the panel carries one stylesheet defining the row rule');

  for (const [tool, config, free] of [
    ['notproton-sikarugir', {}, true],
    ['notproton-freewine', {}, true],
    ['notproton-freewine-26.3_2', {}, true],
    ['notproton', { legacyFree: true }, true],
    ['', { defaultTool: 'notproton-sikarugir' }, true],
    ['', { defaultTool: 'notproton', legacyFree: true }, true],
    ['notproton', {}, false],
    ['notproton-26.3', { legacyFree: true }, false],
  ]) {
    const { render, written: changes } = panel(emit, form, config);
    const ns = walk(render({ details: details('D3DM_ENABLE_METALFX=1 %command%',
                                             { strCompatToolName: tool }) }));
    const backend = ns.find(x => x.type === 'Dropdown');
    t.ok(backend.props.rgOptions.some(x => x.data === 'd3dmetal') === !free,
         `${tool || 'inherited default'} offers D3DMetal only for a paid runner`);
    if (free) {
      t.ok(backend.props.rgOptions[0].label === 'Automatic (DXMT / D9VK)',
           'free Automatic names its actual graphics choices');
      t.ok(backend.props.rgOptions.find(x => x.data === 'dxvk').label.includes('Experimental'),
           'unqualified renderer is labelled experimental');
      t.ok(ns.find(x => x.props.label === 'MSync (Experimental)'),
           'MSync qualification is explicit');
      ns.find(x => x.props.label === 'DLSS (Experimental)').props.onChange(true);
      t.ok(changes.at(-1).opts.includes('DXMT_ENABLE_NVEXT=1'),
           'free Automatic DLSS writes the DXMT option');
      backend.props.onChange({ data: '' });
      t.ok(!changes.at(-1).opts.includes('D3DM_ENABLE_METALFX'),
           'selecting free Automatic clears an incompatible D3DMetal option');
      const enabled = walk(render({ details: details('CX_GRAPHICS_BACKEND=dxmt DXMT_ENABLE_NVEXT=1 %command%',
                                                     { strCompatToolName: tool }) }));
      enabled.find(x => x.type === 'Dropdown').props.onChange({ data: '' });
      t.ok(changes.at(-1).opts.includes('DXMT_ENABLE_NVEXT=1'),
           'switching free DXMT to Automatic preserves its compatible DLSS option');
    }
  }

  for (const tool of ['notproton-sikarugir']) {
    const { render, written: changes } = panel(emit, form);
    const original = "DXMT_CONFIG='dxgi.customVendorId=10de;user.option=True' FOO=keep wrapper %command% --user-arg";
    const props = { unAppID: 1017900, strCompatToolName: tool };
    const ns = walk(render({ details: details(original, props) }));
    const profile = ns.find(x => x.type === 'Section' && x.props.label === 'Game profile: aoe-de-adapter v2');
    t.ok(profile, tool + ' displays the versioned matching profile');
    ns.find(x => x.props.label === "Disable this game's profile").props.onChange(true);
    t.ok(changes.at(-1).opts.includes('NOTPROTON_DISABLE_PROFILES=1') && changes.at(-1).opts.includes(original),
         'disabling preserves explicit renderer settings, wrapper and arguments');
    const disabled = walk(render({ details: details('NOTPROTON_DISABLE_PROFILES=1 ' + original, props) }));
    disabled.find(x => x.type === 'button' && x.props.children === 'Reset profile selection').props.onClick();
    t.ok(changes.at(-1).opts === original, 'reset removes only the profile control');
    for (const mismatch of [{ unAppID: 1151340 }, { strCompatToolName: 'notproton-freewine-unknown' }]) {
      const other = walk(render({ details: details(original, Object.assign({}, props, mismatch)) }));
      t.ok(!other.some(x => x.type === 'Section' && String(x.props.label).startsWith('Game profile:')),
           'unknown game or runtime receives no profile');
    }
    const unsupported = walk(render({ details: details('CX_GRAPHICS_BACKEND=wined3d ' + original, props) }));
    t.ok(!unsupported.some(x => x.props.label === 'Game profile: aoe-de-adapter v2'), 'unmatched renderer receives no profile');
  }

  for (const tool of ['notproton-freewine', 'notproton-freewine-26.3_2']) {
    for (const config of [{}, { defaultTool: tool }]) {
      const { render } = panel(emit, form, config);
      const props = { unAppID: 1017900, strCompatToolName: config.defaultTool ? '' : tool };
      const ns = walk(render({ details: details('CX_GRAPHICS_BACKEND=dxvk %command%', props) }));
      t.ok(!ns.some(x => x.type === 'Section' && String(x.props.label).startsWith('Game profile:')),
           tool + ' does not offer the unqualified Sikarugir adapter profile, including inherited selection');
    }
  }

  failed += t.failed;
}
console.log(failed ? `\n${failed} failure(s)` : '\nboth shapes pass');
process.exit(failed ? 1 : 0);
