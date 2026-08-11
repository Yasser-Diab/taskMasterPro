const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ownerId = process.argv[2];
const outputPath = process.argv[3];

if (!ownerId || !outputPath) {
  throw new Error(
    'Usage: node tool/export_owner_data.cjs <owner-uuid> <output-json>',
  );
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
    const account = await client.query(
      'select user_id, created_at from public.profiles where user_id = $1::uuid',
      [ownerId],
    );
    if (account.rowCount !== 1) {
      throw new Error(
        'The configured owner UUID does not have a canonical public profile.',
      );
    }

    const tables = await client.query(`
      select c.table_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema
       and t.table_name = c.table_name
      where c.table_schema = 'public'
        and c.column_name = 'user_id'
        and t.table_type = 'BASE TABLE'
      order by c.table_name
    `);

    const payload = {
      exported_at: new Date().toISOString(),
      project_ref: 'iejbogkqknldxoyepvun',
      owner_id: ownerId,
      canonical_profile_identity: account.rows[0],
      tables: {},
    };

    for (const { table_name: tableName } of tables.rows) {
      const quoted = `"${tableName.replaceAll('"', '""')}"`;
      const rows = await client.query(
        `select * from public.${quoted} where user_id = $1::uuid`,
        [ownerId],
      );
      payload.tables[tableName] = rows.rows;
    }

    fs.mkdirSync(path.dirname(path.resolve(outputPath)), { recursive: true });
    fs.writeFileSync(
      outputPath,
      JSON.stringify(
        payload,
        (_key, value) =>
          typeof value === 'bigint' ? value.toString() : value,
        2,
      ),
      'utf8',
    );

    const counts = Object.fromEntries(
      Object.entries(payload.tables).map(([name, rows]) => [name, rows.length]),
    );
    process.stdout.write(
      `${JSON.stringify({
        output: path.resolve(outputPath),
        table_count: Object.keys(counts).length,
        row_count: Object.values(counts).reduce(
          (total, count) => total + count,
          0,
        ),
        non_empty_tables: Object.fromEntries(
          Object.entries(counts).filter(([, count]) => count > 0),
        ),
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
