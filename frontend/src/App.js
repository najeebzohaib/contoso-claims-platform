import React, { useState } from "react";
import { submitClaim, searchClaims, analyseClaim } from "./services/claimsApi";

const inputStyle = {
  display: "block", width: "100%", marginTop: 4,
  padding: "8px 12px", border: "1px solid #ccc",
  borderRadius: 4, fontSize: 14, boxSizing: "border-box",
};

const btnStyle = {
  padding: "10px 24px", background: "#0078d4", color: "white",
  border: "none", borderRadius: 4, cursor: "pointer",
  fontSize: 15, fontWeight: 600, alignSelf: "flex-start",
};

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

  return (
    <div style={{ fontFamily: "sans-serif", maxWidth: 900, margin: "0 auto", padding: 24 }}>
      <header style={{ borderBottom: "2px solid #0078d4", paddingBottom: 16, marginBottom: 24 }}>
        <h1 style={{ color: "#0078d4", margin: 0 }}>Contoso Claims Intelligence Platform</h1>
        <p style={{ color: "#666", margin: "4px 0 0" }}>
          Azure OpenAI · Document Intelligence · AI Search · AKS · Databricks
        </p>
      </header>

      <nav style={{ display: "flex", gap: 8, marginBottom: 24 }}>
        {[["submit","Submit Claim"],["search","Search Claims"],["analyse","AI Analysis"]].map(([id, label]) => (
          <button key={id} onClick={() => { setTab(id); setResult(null); setError(null); }}
            style={{ padding: "8px 20px", background: tab===id ? "#0078d4" : "#f0f0f0",
              color: tab===id ? "white" : "#333", border: "none", borderRadius: 4,
              cursor: "pointer", fontWeight: tab===id ? 600 : 400 }}>
            {label}
          </button>
        ))}
      </nav>

      {tab === "submit" && (
        <form onSubmit={e => { e.preventDefault(); wrap(() => submitClaim({...form, claimedAmount: parseFloat(form.claimedAmount)})); }}
          style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <h2>Submit New Claim</h2>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
            <label>Policy Number<input style={inputStyle} value={form.policyNumber}
              onChange={e => setForm({...form, policyNumber: e.target.value})} placeholder="POL-123456" required /></label>
            <label>Claim Type
              <select style={inputStyle} value={form.claimType}
                onChange={e => setForm({...form, claimType: e.target.value})}>
                {["MOTOR","PROPERTY","LIABILITY","HEALTH"].map(t => <option key={t}>{t}</option>)}
              </select>
            </label>
            <label>Incident Date<input type="date" style={inputStyle} value={form.incidentDate}
              onChange={e => setForm({...form, incidentDate: e.target.value})} required /></label>
            <label>Claimed Amount (GBP)<input type="number" style={inputStyle} value={form.claimedAmount}
              onChange={e => setForm({...form, claimedAmount: e.target.value})} placeholder="5000.00" required /></label>
          </div>
          <label>Description<textarea style={{...inputStyle, height: 100, resize: "vertical"}}
            value={form.description} onChange={e => setForm({...form, description: e.target.value})}
            placeholder="Describe the incident..." required /></label>
          <button type="submit" style={btnStyle} disabled={loading}>{loading ? "Submitting..." : "Submit Claim"}</button>
        </form>
      )}

      {tab === "search" && (
        <form onSubmit={e => { e.preventDefault(); wrap(() => searchClaims(searchQ)); }}
          style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <h2>Semantic Search — Azure AI Search + OpenAI</h2>
          <label>Query<input style={inputStyle} value={searchQ}
            onChange={e => setSearchQ(e.target.value)}
            placeholder="Find claims involving flood damage to commercial property..." required /></label>
          <button type="submit" style={btnStyle} disabled={loading}>{loading ? "Searching..." : "Search"}</button>
        </form>
      )}

      {tab === "analyse" && (
        <form onSubmit={e => { e.preventDefault(); wrap(() => analyseClaim(analyseId)); }}
          style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <h2>AI Analysis — Azure OpenAI GPT-4</h2>
          <p style={{ color: "#666" }}>Analyse a claim to extract key facts, assess risk, and generate a structured summary.</p>
          <label>Claim ID<input style={inputStyle} value={analyseId}
            onChange={e => setAnalyseId(e.target.value)} placeholder="CLM-2025-001234" required /></label>
          <button type="submit" style={btnStyle} disabled={loading}>{loading ? "Analysing..." : "Analyse with AI"}</button>
        </form>
      )}

      {error && <div style={{ marginTop: 16, padding: 16, background: "#fde",
        border: "1px solid #f88", borderRadius: 4 }}><strong>Error:</strong> {error}</div>}

      {result && <div style={{ marginTop: 16, padding: 16, background: "#f0f8ff",
        border: "1px solid #0078d4", borderRadius: 4 }}>
        <strong>Result:</strong>
        <pre style={{ margin: "8px 0 0", overflow: "auto", fontSize: 13 }}>{JSON.stringify(result, null, 2)}</pre>
      </div>}
    </div>
  );
}
