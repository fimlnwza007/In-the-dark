const fs = require('fs');
const content = fs.readFileSync('Scenes/start_scene.tscn', 'utf8');

const subresources = [];
const subRegex = /\[sub_resource type="[^"]+" id="([^"]+)"\]/g;
let m;
while ((m = subRegex.exec(content)) !== null) {
    subresources.push(m[1]);
}

const refs = [];
const refRegex = /SubResource\("([^"]+)"\)/g;
while ((m = refRegex.exec(content)) !== null) {
    refs.push(m[1]);
}

const missing = refs.filter(r => !subresources.includes(r));
console.log('Defined subresources:', subresources);
console.log('Referenced subresources:', [...new Set(refs)]);
console.log('Missing:', missing.length === 0 ? 'NONE! 100% VALID!' : missing);
