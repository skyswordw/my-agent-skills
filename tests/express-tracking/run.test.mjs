import assert from "node:assert/strict";
import crypto from "node:crypto";
import { mkdirSync, readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  cleanupDir,
  makeTempDir,
  readFixture,
  runCli,
  startMockKuaidi100Server,
  writeEnvLocal
} from "./test-helpers.mjs";

test("cli prints a Chinese summary, falls back to heuristic detection, and respects --recent-limit", async () => {
  const tempDir = makeTempDir("express-tracking-run-");
  const server = await startMockKuaidi100Server({
    autoPayload: JSON.parse(readFixture("auto-disabled.json")),
    queryPayload: JSON.parse(readFixture("query-ok.json"))
  });

  try {
    const projectDir = path.join(tempDir, "project");
    mkdirSync(projectDir, { recursive: true });
    writeEnvLocal(projectDir, {
      EXPRESS_TRACKING_KUAIDI100_KEY: "test-key",
      EXPRESS_TRACKING_KUAIDI100_CUSTOMER: "test-customer",
      EXPRESS_TRACKING_KUAIDI100_QUERY_URL: `${server.baseUrl}/poll/query.do`,
      EXPRESS_TRACKING_KUAIDI100_AUTO_URL: `${server.baseUrl}/autonumber/auto`,
      EXPRESS_TRACKING_DEFAULT_RECENT_LIMIT: "2"
    });

    const result = await runCli({
      cwd: projectDir,
      args: ["--number=JDVE17645695946", "--recent-limit=1"]
    });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /快递单号：JDVE17645695946/);
    assert.match(result.stdout, /快递公司：jd（前缀推断）/);
    assert.match(result.stdout, /物流状态：在途/);
    assert.match(result.stdout, /最近轨迹：/);
    assert.equal((result.stdout.match(/^- /gmu) ?? []).length, 1);
  } finally {
    await server.close();
    cleanupDir(tempDir);
  }
});

test("cli emits stable JSON and sends a correct Kuaidi100 signed query", async () => {
  const tempDir = makeTempDir("express-tracking-json-");
  const queryPayload = JSON.parse(readFixture("query-ok.json"));
  const server = await startMockKuaidi100Server({
    autoPayload: {
      returnCode: "200",
      message: "ok",
      data: [{ comCode: "jd" }]
    },
    queryPayload
  });

  try {
    const projectDir = path.join(tempDir, "project");
    mkdirSync(projectDir, { recursive: true });
    writeEnvLocal(projectDir, {
      EXPRESS_TRACKING_KUAIDI100_KEY: "test-key",
      EXPRESS_TRACKING_KUAIDI100_CUSTOMER: "test-customer",
      EXPRESS_TRACKING_KUAIDI100_QUERY_URL: `${server.baseUrl}/poll/query.do`,
      EXPRESS_TRACKING_KUAIDI100_AUTO_URL: `${server.baseUrl}/autonumber/auto`
    });

    const result = await runCli({
      cwd: projectDir,
      args: ["--number=JDVE17645695946", "--json", "--recent-limit=1"]
    });

    assert.equal(result.status, 0, result.stderr);
    const payload = JSON.parse(result.stdout);

    assert.deepEqual(payload, {
      provider: "kuaidi100",
      number: "JDVE17645695946",
      carrier: {
        code: "jd",
        source: "auto"
      },
      state: {
        code: "0",
        label: "在途"
      },
      status: {
        code: "200",
        message: "ok"
      },
      latestEvent: {
        time: "2026-04-23 20:34:37",
        context: "您的快件已离开【北京顺义集货分拣中心】，正在发往下一站【天津散货分拣中心】的路上。"
      },
      recentEvents: [
        {
          time: "2026-04-23 20:34:37",
          context: "您的快件已离开【北京顺义集货分拣中心】，正在发往下一站【天津散货分拣中心】的路上。"
        }
      ]
    });

    assert.equal(server.requests.auto.length, 1);
    assert.equal(server.requests.query.length, 1);
    const [queryRequest] = server.requests.query;
    assert.equal(queryRequest.form.get("customer"), "test-customer");

    const param = queryRequest.form.get("param");
    assert.equal(
      param,
      JSON.stringify({
        num: "JDVE17645695946",
        com: "jd",
        phone: "",
        from: "",
        to: "",
        resultv2: "1",
        show: "0",
        order: "desc"
      })
    );

    const expectedSign = crypto
      .createHash("md5")
      .update(`${param}test-keytest-customer`, "utf8")
      .digest("hex")
      .toUpperCase();
    assert.equal(queryRequest.form.get("sign"), expectedSign);
  } finally {
    await server.close();
    cleanupDir(tempDir);
  }
});

test("cli honors an explicit --carrier override and bypasses auto plus heuristic resolution", async () => {
  const tempDir = makeTempDir("express-tracking-explicit-carrier-");
  const server = await startMockKuaidi100Server({
    autoPayload: {
      returnCode: "200",
      message: "ok",
      data: [{ comCode: "ems" }]
    },
    queryPayload: JSON.parse(readFixture("query-ok.json"))
  });

  try {
    const projectDir = path.join(tempDir, "project");
    mkdirSync(projectDir, { recursive: true });
    writeEnvLocal(projectDir, {
      EXPRESS_TRACKING_KUAIDI100_KEY: "test-key",
      EXPRESS_TRACKING_KUAIDI100_CUSTOMER: "test-customer",
      EXPRESS_TRACKING_KUAIDI100_QUERY_URL: `${server.baseUrl}/poll/query.do`,
      EXPRESS_TRACKING_KUAIDI100_AUTO_URL: `${server.baseUrl}/autonumber/auto`
    });

    const result = await runCli({
      cwd: projectDir,
      args: ["--number=JDVE17645695946", "--carrier=shunfeng", "--recent-limit=1"]
    });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /快递公司：shunfeng（手动指定）/);
    assert.equal(server.requests.auto.length, 0);
    assert.equal(server.requests.query.length, 1);
    assert.equal(server.requests.query[0].form.get("param"), JSON.stringify({
      num: "JDVE17645695946",
      com: "shunfeng",
      phone: "",
      from: "",
      to: "",
      resultv2: "1",
      show: "0",
      order: "desc"
    }));
  } finally {
    await server.close();
    cleanupDir(tempDir);
  }
});

test("cli fails clearly when carrier detection cannot resolve a company code", async () => {
  const tempDir = makeTempDir("express-tracking-failure-");
  const server = await startMockKuaidi100Server({
    autoPayload: JSON.parse(readFixture("auto-disabled.json")),
    queryPayload: JSON.parse(readFixture("query-ok.json"))
  });

  try {
    const projectDir = path.join(tempDir, "project");
    mkdirSync(projectDir, { recursive: true });
    writeEnvLocal(projectDir, {
      EXPRESS_TRACKING_KUAIDI100_KEY: "test-key",
      EXPRESS_TRACKING_KUAIDI100_CUSTOMER: "test-customer",
      EXPRESS_TRACKING_KUAIDI100_QUERY_URL: `${server.baseUrl}/poll/query.do`,
      EXPRESS_TRACKING_KUAIDI100_AUTO_URL: `${server.baseUrl}/autonumber/auto`
    });

    const result = await runCli({
      cwd: projectDir,
      args: ["--number=UNKNOWN123"]
    });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /无法自动识别快递公司/);
    assert.match(result.stderr, /--carrier=/);
  } finally {
    await server.close();
    cleanupDir(tempDir);
  }
});

test("cli fails clearly when Kuaidi100 credentials are missing", async () => {
  const tempDir = makeTempDir("express-tracking-missing-config-");
  try {
    const projectDir = path.join(tempDir, "project");
    mkdirSync(projectDir, { recursive: true });

    const result = await runCli({
      cwd: projectDir,
      args: ["--number=SF123456789CN"]
    });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /缺少 EXPRESS_TRACKING_KUAIDI100_KEY/);
  } finally {
    cleanupDir(tempDir);
  }
});
