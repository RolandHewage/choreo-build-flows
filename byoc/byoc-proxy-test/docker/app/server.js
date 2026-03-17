const express = require("express");
const app = express();
const port = 8080;

app.get("/greeting", (req, res) => {
  const name = req.query.name || "World";
  res.json({ greeting: `Hello, ${name}!` });
});

app.listen(port, () => {
  console.log(`Greeting service listening on port ${port}`);
});
