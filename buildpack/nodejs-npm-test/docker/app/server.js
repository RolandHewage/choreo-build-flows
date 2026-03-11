const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({
    message: 'npm proxy E2E test — build succeeded!',
    expressVersion: require('express/package.json').version,
  });
});

app.listen(port, () => {
  console.log(`npm proxy E2E test — build succeeded!`);
  console.log(`  express version: ${require('express/package.json').version}`);
  console.log(`  listening on port ${port}`);
});
