const APIM_BASE_URL = process.env.REACT_APP_APIM_URL || "";
const APIM_KEY = process.env.REACT_APP_APIM_KEY || "";

const headers = () => ({
  "Content-Type": "application/json",
  "Ocp-Apim-Subscription-Key": APIM_KEY,
});

export const submitClaim = async (data) => {
  const r = await fetch(`${APIM_BASE_URL}/claims/v1/submit`, {
    method: "POST", headers: headers(), body: JSON.stringify(data),
  });
  if (!r.ok) throw new Error(r.statusText);
  return r.json();
};

export const searchClaims = async (query) => {
  const r = await fetch(`${APIM_BASE_URL}/claims/v1/search?q=${encodeURIComponent(query)}`, {
    headers: headers(),
  });
  if (!r.ok) throw new Error(r.statusText);
  return r.json();
};

export const analyseClaim = async (claimId) => {
  const r = await fetch(`${APIM_BASE_URL}/claims/v1/${claimId}/analyse`, {
    method: "POST", headers: headers(),
  });
  if (!r.ok) throw new Error(r.statusText);
  return r.json();
};
