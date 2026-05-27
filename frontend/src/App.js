import React, { useState } from "react";
import { submitClaim, searchClaims, analyseClaim } from "./services/claimsApi";

const APIM_URL = process.env.REACT_APP_APIM_URL || "http://4.158.34.10";

const colors = {
  blue: "#0078d4", blueDark: "#005a9e", blueLight: "#deecf9",
  green: "#107c10", greenLight: "#dff6dd",
  amber: "#ff8c00", amberLight: "#fff4ce",
  red: "#d13438", redLight: "#fde7e9",
  gray: "#605e5c", grayLight: "#f3f2f1", grayBorder: "#edebe9",
  white: "#ffffff", dark: "#201f1e",
};

const riskColors = {
  HIGH:   { bg: colors.redLight,   text: colors.red,   bar: colors.red },
  MEDIUM: { bg: colors.amberLight, text: colors.amber,  bar: colors.amber },
  LOW:    { bg: colors.greenLight, text: colors.green,  bar: colors.green },
};

const card = {
  background: colors.white, borderRadius: 8,
  border: `1px solid ${colors.grayBorder}`,
  boxShadow: "0 2px 8px rgba(0,0,0,0.06)", padding: "28px 32px",
};

const inputStyle = {
  display: "block", width: "100%", marginTop: 6,
  padding: "9px 12px", border: `1px solid ${colors.grayBorder}`,
  borderRadius: 4, fontSize: 14, boxSizing: "border-box",
  background: colors.white, color: colors.dark, outline: "none",
  fontFamily: "inherit",
};

const labelStyle = { fontSize: 13, fontWeight: 600, color: colors.gray, display: "block" };

function Badge({ children, color, bg }) {
  return (
    <span style={{
      display: "inline-block", padding: "3px 10px", borderRadius: 12,
      fontSize: 12, fontWeight: 700, background: bg, color: color,
      letterSpacing: "0.5px", textTransform: "uppercase",
    }}>{children}</span>
  );
}

function RiskGauge({ score, band }) {
  const c = riskColors[band] || riskColors.LOW;
  const pct = Math.round(score * 100);
  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
        <span style={{ fontSize: 13, color: colors.gray }}>Risk score</span>
        <span style={{ fontSize: 13, fontWeight: 700, color: c.text }}>{pct}%</span>
      </div>
      <div style={{ height: 8, background: colors.grayBorder, borderRadius: 4, overflow: "hidden" }}>
        <div style={{
          width: `${pct}%`, height: "100%", background: c.bar,
          borderRadius: 4, transition: "width 0.8s ease",
        }}/>
      </div>
    </div>
  );
}

function Spinner() {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10, color: colors.gray, margin: "20px 0" }}>
      <div style={{
        width: 20, height: 20, border: `2px solid ${colors.grayBorder}`,
        borderTop: `2px solid ${colors.blue}`, borderRadius: "50%",
        animation: "spin 0.8s linear infinite",
      }}/>
      <span style={{ fontSize: 14 }}>Processing via Azure AI…</span>
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}

function ClaimCard({ claim }) {
  if (!claim) return null;
  const statusColors = {
    SUBMITTED: { bg: colors.blueLight, text: colors.blue },
    ANALYSED:  { bg: colors.greenLight, text: colors.green },
    APPROVED:  { bg: colors.greenLight, text: colors.green },
    REJECTED:  { bg: colors.redLight, text: colors.red },
    INVESTIGATION: { bg: colors.amberLight, text: colors.amber },
  };
  const sc = statusColors[claim.status] || statusColors.SUBMITTED;
  return (
    <div style={{ ...card, borderLeft: `4px solid ${colors.blue}`, marginTop: 20 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 16 }}>
        <div>
          <p style={{ margin: 0, fontSize: 11, color: colors.gray, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.5px" }}>Claim submitted</p>
          <h3 style={{ margin: "4px 0 0", fontSize: 20, color: colors.dark, fontWeight: 700 }}>{claim.claimId}</h3>
        </div>
        <Badge color={sc.text} bg={sc.bg}>{claim.status}</Badge>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 16, marginBottom: 12 }}>
        <div><span style={labelStyle}>Policy</span><p style={{ margin: "2px 0", fontSize: 15, color: colors.dark }}>{claim.policyNumber}</p></div>
        <div><span style={labelStyle}>Type</span><p style={{ margin: "2px 0", fontSize: 15, color: colors.dark }}>{claim.claimType}</p></div>
        <div><span style={labelStyle}>Amount</span><p style={{ margin: "2px 0", fontSize: 15, fontWeight: 700, color: colors.blue }}>£{Number(claim.claimedAmount).toLocaleString()}</p></div>
      </div>
      <div style={{ background: colors.grayLight, borderRadius: 6, padding: "10px 14px", fontSize: 13, color: colors.gray }}>
        {claim.description}
      </div>
      <p style={{ margin: "10px 0 0", fontSize: 12, color: colors.gray }}>Submitted {new Date(claim.submittedAt).toLocaleString()}</p>
    </div>
  );
}

function AnalysisCard({ result }) {
  if (!result || !result.riskBand) return null;
  const c = riskColors[result.riskBand] || riskColors.LOW;
  const recColors = {
    APPROVE:     { bg: colors.greenLight, text: colors.green },
    INVESTIGATE: { bg: colors.amberLight, text: colors.amber },
    REJECT:      { bg: colors.redLight,   text: colors.red },
  };
  const rc = recColors[result.recommendation] || recColors.INVESTIGATE;
  return (
    <div style={{ ...card, borderLeft: `4px solid ${c.bar}`, marginTop: 20 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <p style={{ margin: 0, fontSize: 11, color: colors.gray, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.5px" }}>GPT-4o Analysis</p>
          <h3 style={{ margin: "4px 0 0", fontSize: 18, color: colors.dark }}>{result.claimId}</h3>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <Badge color={c.text} bg={c.bg}>{result.riskBand} RISK</Badge>
          <Badge color={rc.text} bg={rc.bg}>{result.recommendation}</Badge>
        </div>
      </div>

      <RiskGauge score={result.riskScore || 0} band={result.riskBand} />

      <div style={{ marginTop: 20, padding: "14px 16px", background: colors.grayLight, borderRadius: 6, fontSize: 14, color: colors.dark, lineHeight: 1.6 }}>
        <strong style={{ display: "block", marginBottom: 4, color: colors.gray, fontSize: 12, textTransform: "uppercase", letterSpacing: "0.5px" }}>AI Summary</strong>
        {result.summary}
      </div>

      {result.fraudIndicators && result.fraudIndicators.length > 0 && (
        <div style={{ marginTop: 16 }}>
          <p style={{ margin: "0 0 8px", fontSize: 12, fontWeight: 700, color: colors.red, textTransform: "uppercase", letterSpacing: "0.5px" }}>⚠ Fraud indicators detected</p>
          {result.fraudIndicators.map((fi, i) => (
            <div key={i} style={{ display: "flex", gap: 8, marginBottom: 6, alignItems: "flex-start" }}>
              <span style={{ color: colors.red, fontSize: 16, marginTop: -1 }}>•</span>
              <span style={{ fontSize: 13, color: colors.dark }}>{typeof fi === "string" ? fi : fi.indicator || JSON.stringify(fi)}</span>
            </div>
          ))}
        </div>
      )}

      {result.keyFacts && (
        <div style={{ marginTop: 16 }}>
          <p style={{ margin: "0 0 8px", fontSize: 12, fontWeight: 700, color: colors.gray, textTransform: "uppercase", letterSpacing: "0.5px" }}>Key facts extracted</p>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
            {Object.entries(result.keyFacts).filter(([,v]) => v !== null && v !== undefined).map(([k, v]) => (
              <div key={k} style={{ background: colors.grayLight, borderRadius: 6, padding: "8px 12px" }}>
                <span style={{ fontSize: 11, color: colors.gray, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.4px" }}>{k.replace(/([A-Z])/g, " $1").trim()}</span>
                <p style={{ margin: "2px 0 0", fontSize: 13, color: colors.dark }}>{String(v)}</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default function App() {
  const [tab, setTab] = useState("submit");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [form, setForm] = useState({
    policyNumber: "", claimType: "MOTOR", incidentDate: "",
    claimedAmount: "", currency: "GBP", description: "",
  });
  const [searchQ, setSearchQ] = useState("");
  const [analyseId, setAnalyseId] = useState("");

  const wrap = async (fn) => {
    setLoading(true); setError(null); setResult(null);
    try { setResult(await fn()); }
    catch (e) { setError(e.message); }
    finally { setLoading(false); }
  };

  const tabs = [
    { id: "submit",  label: "Submit claim",  icon: "📋" },
    { id: "search",  label: "Search claims", icon: "🔍" },
    { id: "analyse", label: "AI analysis",   icon: "🤖" },
  ];

  return (
    <div style={{ fontFamily: "'Segoe UI', system-ui, sans-serif", minHeight: "100vh", background: "#faf9f8" }}>
      {/* Header */}
      <div style={{ background: colors.blue, padding: "0 40px" }}>
        <div style={{ maxWidth: 960, margin: "0 auto", padding: "20px 0" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div style={{ width: 40, height: 40, background: "rgba(255,255,255,0.2)", borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 20 }}>🛡</div>
            <div>
              <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: colors.white }}>Contoso Claims Intelligence</h1>
              <p style={{ margin: 0, fontSize: 13, color: "rgba(255,255,255,0.75)" }}>Azure OpenAI GPT-4o  ·  Document Intelligence  ·  AI Search  ·  AKS  ·  Databricks</p>
            </div>
          </div>
        </div>
      </div>

      {/* Stack badge */}
      <div style={{ background: colors.blueDark, padding: "8px 40px" }}>
        <div style={{ maxWidth: 960, margin: "0 auto", display: "flex", gap: 16, flexWrap: "wrap" }}>
          {["Azure Firewall Premium","App Gateway WAF","API Management","AKS + Workload Identity","Private Endpoints","Sentinel SIEM"].map(s => (
            <span key={s} style={{ fontSize: 11, color: "rgba(255,255,255,0.7)", fontWeight: 500 }}>✓ {s}</span>
          ))}
        </div>
      </div>

      {/* Main */}
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "32px 40px" }}>

        {/* Tabs */}
        <div style={{ display: "flex", gap: 4, marginBottom: 28, background: colors.white, border: `1px solid ${colors.grayBorder}`, borderRadius: 8, padding: 4, width: "fit-content" }}>
          {tabs.map(({ id, label, icon }) => (
            <button key={id} onClick={() => { setTab(id); setResult(null); setError(null); }}
              style={{
                padding: "8px 20px", border: "none", borderRadius: 6, cursor: "pointer",
                background: tab === id ? colors.blue : "transparent",
                color: tab === id ? colors.white : colors.gray,
                fontWeight: tab === id ? 600 : 400, fontSize: 14, fontFamily: "inherit",
                transition: "all 0.15s",
              }}>
              {icon} {label}
            </button>
          ))}
        </div>

        {/* Submit */}
        {tab === "submit" && (
          <div style={card}>
            <h2 style={{ margin: "0 0 6px", fontSize: 18, color: colors.dark }}>Submit a new claim</h2>
            <p style={{ margin: "0 0 24px", fontSize: 13, color: colors.gray }}>Claims are processed through Azure API Management and stored on AKS. AI analysis is available after submission.</p>
            <form onSubmit={e => { e.preventDefault(); wrap(() => submitClaim({ ...form, claimedAmount: parseFloat(form.claimedAmount) })); }}>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20, marginBottom: 20 }}>
                <label><span style={labelStyle}>Policy number</span>
                  <input style={inputStyle} value={form.policyNumber} onChange={e => setForm({ ...form, policyNumber: e.target.value })} placeholder="POL-BOE-2026-001" required />
                </label>
                <label><span style={labelStyle}>Claim type</span>
                  <select style={inputStyle} value={form.claimType} onChange={e => setForm({ ...form, claimType: e.target.value })}>
                    {["MOTOR", "PROPERTY", "LIABILITY", "HEALTH"].map(t => <option key={t}>{t}</option>)}
                  </select>
                </label>
                <label><span style={labelStyle}>Incident date</span>
                  <input type="date" style={inputStyle} value={form.incidentDate} onChange={e => setForm({ ...form, incidentDate: e.target.value })} required />
                </label>
                <label><span style={labelStyle}>Claimed amount (GBP)</span>
                  <input type="number" style={inputStyle} value={form.claimedAmount} onChange={e => setForm({ ...form, claimedAmount: e.target.value })} placeholder="45000" required />
                </label>
              </div>
              <label style={{ display: "block", marginBottom: 20 }}>
                <span style={labelStyle}>Incident description</span>
                <textarea style={{ ...inputStyle, height: 100, resize: "vertical" }} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Describe the incident in detail..." required />
              </label>
              <button type="submit" disabled={loading} style={{
                padding: "10px 28px", background: loading ? colors.grayBorder : colors.blue,
                color: colors.white, border: "none", borderRadius: 6, cursor: loading ? "not-allowed" : "pointer",
                fontSize: 14, fontWeight: 600, fontFamily: "inherit",
              }}>{loading ? "Submitting…" : "Submit claim →"}</button>
            </form>
            {loading && <Spinner />}
            {error && <div style={{ marginTop: 16, padding: "12px 16px", background: colors.redLight, borderRadius: 6, color: colors.red, fontSize: 13 }}>⚠ {error}</div>}
            {result && <ClaimCard claim={result} />}
          </div>
        )}

        {/* Search */}
        {tab === "search" && (
          <div style={card}>
            <h2 style={{ margin: "0 0 6px", fontSize: 18, color: colors.dark }}>Search claims</h2>
            <p style={{ margin: "0 0 24px", fontSize: 13, color: colors.gray }}>Full-text and semantic search powered by Azure AI Search with vector embeddings.</p>
            <div style={{ display: "flex", gap: 12, marginBottom: 20 }}>
              <input style={{ ...inputStyle, marginTop: 0, flex: 1 }} value={searchQ} onChange={e => setSearchQ(e.target.value)}
                placeholder="Search by description, claim type, policy number…"
                onKeyDown={e => e.key === "Enter" && wrap(() => searchClaims(searchQ))} />
              <button onClick={() => wrap(() => searchClaims(searchQ))} disabled={loading} style={{
                padding: "9px 24px", background: colors.blue, color: colors.white, border: "none",
                borderRadius: 4, cursor: "pointer", fontSize: 14, fontWeight: 600, fontFamily: "inherit", whiteSpace: "nowrap",
              }}>Search</button>
            </div>
            {loading && <Spinner />}
            {error && <div style={{ padding: "12px 16px", background: colors.redLight, borderRadius: 6, color: colors.red, fontSize: 13 }}>⚠ {error}</div>}
            {result && (
              <div>
                <p style={{ fontSize: 13, color: colors.gray, margin: "0 0 12px" }}>{result.count || result.results?.length || 0} results for "{result.query}"</p>
                {(result.results || []).map((r, i) => (
                  <div key={i} style={{ padding: "14px 16px", border: `1px solid ${colors.grayBorder}`, borderRadius: 6, marginBottom: 8, background: colors.white }}>
                    <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
                      <span style={{ fontWeight: 700, color: colors.blue, fontSize: 14 }}>{r.claimId || r.claim_id}</span>
                      <Badge color={colors.blue} bg={colors.blueLight}>{r.claimType || r.claim_type}</Badge>
                    </div>
                    <p style={{ margin: 0, fontSize: 13, color: colors.gray }}>{r.description}</p>
                  </div>
                ))}
                {(!result.results || result.results.length === 0) && (
                  <div style={{ padding: "20px", textAlign: "center", color: colors.gray, fontSize: 14 }}>No results found. Try a different search term.</div>
                )}
              </div>
            )}
          </div>
        )}

        {/* Analyse */}
        {tab === "analyse" && (
          <div style={card}>
            <h2 style={{ margin: "0 0 6px", fontSize: 18, color: colors.dark }}>AI-powered claim analysis</h2>
            <p style={{ margin: "0 0 24px", fontSize: 13, color: colors.gray }}>GPT-4o analyses the claim and returns a structured risk score, fraud indicators, and recommendation — all via Azure OpenAI on private endpoints.</p>
            <div style={{ display: "flex", gap: 12, marginBottom: 8 }}>
              <input style={{ ...inputStyle, marginTop: 0, flex: 1 }} value={analyseId} onChange={e => setAnalyseId(e.target.value)}
                placeholder="CLM-20260527-XXXXXXXX"
                onKeyDown={e => e.key === "Enter" && wrap(() => analyseClaim(analyseId))} />
              <button onClick={() => wrap(() => analyseClaim(analyseId))} disabled={loading || !analyseId} style={{
                padding: "9px 24px", background: analyseId ? colors.blue : colors.grayBorder,
                color: analyseId ? colors.white : colors.gray, border: "none",
                borderRadius: 4, cursor: analyseId ? "pointer" : "not-allowed",
                fontSize: 14, fontWeight: 600, fontFamily: "inherit", whiteSpace: "nowrap",
              }}>Analyse with GPT-4o</button>
            </div>
            <p style={{ margin: "0 0 20px", fontSize: 12, color: colors.gray }}>Submit a claim first to get a Claim ID, then paste it above.</p>
            {loading && <Spinner />}
            {error && <div style={{ padding: "12px 16px", background: colors.redLight, borderRadius: 6, color: colors.red, fontSize: 13 }}>⚠ {error}</div>}
            {result && <AnalysisCard result={result} />}
          </div>
        )}

        {/* Footer */}
        <div style={{ marginTop: 40, paddingTop: 20, borderTop: `1px solid ${colors.grayBorder}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ fontSize: 12, color: colors.gray }}>Contoso Claims Intelligence Platform · Azure UK South</span>
          <div style={{ display: "flex", gap: 16 }}>
            {["Azure Firewall", "WAF v2", "APIM", "AKS", "GPT-4o", "Databricks"].map(s => (
              <span key={s} style={{ fontSize: 11, color: colors.gray, background: colors.grayLight, padding: "3px 8px", borderRadius: 4 }}>{s}</span>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
