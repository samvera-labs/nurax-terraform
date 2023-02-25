const { Client } = require("pg");

function createDb(event) {
  const { user, schema, schema_password } = event;
  return [
    { query: `CREATE ROLE ${schema};`, required: false },
    {
      query: `ALTER ROLE ${schema} WITH LOGIN ENCRYPTED PASSWORD '${schema_password}';`,
      required: true,
    },
    { query: `GRANT ${schema} TO ${user};`, required: true },
    { query: `CREATE DATABASE ${schema} OWNER ${schema};`, required: true },
  ];
}

async function handler(event) {
  const client = new Client({
    ...event,
    database: event.database || "postgres",
  });
  await client.connect();
  const queries = event.queries || createDb(event);
  const results = [];
  for (const { query, required } of queries) {
    try {
      results.push((await client.query(query)).rows);
    } catch (err) {
      if (required) {
        throw err;
      } else {
        results.push(err);
      }
    }
  }
  await client.end();
  return event.queries
    ? results
    : { username: event.schema, password: event.schema_password };
}

module.exports = { handler };
