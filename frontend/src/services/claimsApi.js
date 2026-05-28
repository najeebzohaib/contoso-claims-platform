const APIM_BASE_URL = process.env.REACT_APP_APIM_URL || "http://4.158.34.10";
const APIM_KEY = process.env.REACT_APP_APIM_KEY || "";

const headers = () => ({
  "Content-Type": "application/json",
  ...(APIM_KEY && { "Ocp-Apim-Subscription-Key": APIM_KEY }),
});

export const submitClaim = async (data) => {
  const r = await fetch(`${APIM_BASE_URL}/claims/v1/submit`, {
    method: "POST", headers: headers(), body: JSON.stringify(data),
  });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  return r.json();
};

export const searchClaims = async (query) => {
  // Fetch all claims and filter client-side (search endpoint conflicts with APIM routing)
  const r = await fetch(`${APIM_BASE_URL}/claims/v1`, {
    headers: headers(),
  });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  const data = await r.json();
  const claims = data.claims || [];
  const q = query.toLowerCase();
  const results = claims.filter(c =>
    (c.description || '').toLowerCase().includes(q) ||
    (c.claimType || '').toLowerCase().includes(q) ||
    (c.policyNumber || '').toLowerCase().includes(q) ||
    (c.status || '').toLowerCase().includes(q)
  );
  return { results, count: results.length, query };
};

export const analyseClaim = async (claimId) => {
  const r = await fetch(`${APIM_BASE_URL}/claims/v1/${claimId}/analyse`, {
    method: "POST", headers: headers(),
  });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  return r.json();
};
