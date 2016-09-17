const fs = require('fs');
var filename = process.argv[2];
console.log(filename);
var file = fs.readFileSync(filename, 'utf8');
var json = JSON.parse(file);
json.data = json.data.map(function(point) {
  if (point < 0) {
    return 0;
  } else {
    return point;
  }
});
fs.writeFileSync(filename, JSON.stringify(json));
