const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const sqlPath = process.argv[2];
if (!sqlPath) {
  throw new Error('Usage: node tool/run_linked_sql.cjs <sql-file>');
}

function linkedDatabaseConfig() {
  const located = spawnSync('where.exe', ['supabase'], {
    encoding: 'utf8',
    windowsHide: true,
  });
  const executable = (located.stdout ?? '').split(/\r?\n/).find(Boolean);
  if (!executable) {
    throw new Error('Supabase CLI is not available on PATH.');
  }
  const command = spawnSync(
    executable,
    ['db', 'dump', '--linked', '--dry-run'],
    {
      cwd: path.resolve(__dirname, '..'),
      encoding: 'utf8',
      windowsHide: true,
    },
  );
  const output = `${command.stdout ?? ''}\n${command.stderr ?? ''}`;
  if (command.status !== 0) {
    throw new Error('Could not obtain the linked Supabase connection settings.');
  }

  const value = (name) => {
    const match = output.match(
      new RegExp(`export ${name}="([^"]+)"`, 'm'),
    );
    if (!match) {
      throw new Error(`Missing ${name} in linked Supabase settings.`);
    }
    return match[1];
  };

  return {
    host: value('PGHOST'),
    port: Number(value('PGPORT')),
    user: value('PGUSER'),
    password: value('PGPASSWORD'),
    database: value('PGDATABASE'),
    ssl: { rejectUnauthorized: false },
  };
}

async function main() {
  const pgPath = path.join(
    os.tmpdir(),
    'taskmaster-pg-inspect',
    'node_modules',
    'pg',
  );
  const { Client } = require(pgPath);
  const client = new Client(linkedDatabaseConfig());
  await client.connect();
  try {
    await client.query('set role postgres');
    const sql = fs.readFileSync(path.resolve(sqlPath), 'utf8');
    const result = await client.query(sql);
    const tail = Array.isArray(result) ? result.at(-1) : result;
    process.stdout.write(
      `${JSON.stringify({
        command: tail?.command ?? null,
        row_count: tail?.rowCount ?? null,
        rows: tail?.rows ?? [],
      })}\n`,
    );
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
