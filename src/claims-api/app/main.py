from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import os
import uuid
import logging
from datetime import datetime

from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from openai import AzureOpenAI

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# App Insights via simple HTTP logging
import os
APPINSIGHTS_CS = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING", "")

app = FastAPI(
    title="Contoso Claims Intelligence API",
    description="AI-powered claims processing API",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory store for demo
claims_store = {}

credential = DefaultAzureCredential()

OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT", "")
SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT", "")
SEARCH_INDEX    = os.getenv("AZURE_SEARCH_INDEX", "claims-index")


class ClaimSubmission(BaseModel):
    policyNumber: str
    claimType: str
    incidentDate: str
    claimedAmount: float
    currency: str = "GBP"
    description: str


class ClaimResponse(BaseModel):
    claimId: str
    status: str
    submittedAt: str
    policyNumber: str
    claimType: str
    claimedAmount: float
    currency: str
    description: str


@app.get("/health")
def health():
    return {"status": "healthy", "version": "1.0.0"}


@app.post("/v1/submit", response_model=ClaimResponse)
@app.post("/claims/v1/submit", response_model=ClaimResponse)
async def submit_claim(claim: ClaimSubmission):
    claim_id = f"CLM-{datetime.now().strftime('%Y%m%d')}-{str(uuid.uuid4())[:8].upper()}"
    record = {
        "claimId": claim_id,
        "status": "SUBMITTED",
        "submittedAt": datetime.utcnow().isoformat(),
        "policyNumber": claim.policyNumber,
        "claimType": claim.claimType,
        "incidentDate": claim.incidentDate,
        "claimedAmount": claim.claimedAmount,
        "currency": claim.currency,
        "description": claim.description,
    }
    claims_store[claim_id] = record
    logger.info(f"Claim submitted: {claim_id}")
    return record


@app.get("/v1/{claim_id}", response_model=ClaimResponse)
@app.get("/claims/v1/{claim_id}", response_model=ClaimResponse)
async def get_claim(claim_id: str):
    if claim_id not in claims_store:
        raise HTTPException(status_code=404, detail="Claim not found")
    return claims_store[claim_id]


@app.get("/v1")
@app.get("/claims/v1")
async def list_claims():
    return {"claims": list(claims_store.values()), "total": len(claims_store)}


@app.get("/v1/search")
@app.get("/claims/v1/search")
async def search_claims(q: str):
    if not SEARCH_ENDPOINT:
        # Fallback: search in-memory store
        results = [
            c for c in claims_store.values()
            if q.lower() in c["description"].lower() or q.lower() in c["claimType"].lower()
        ]
        return {"results": results, "count": len(results), "query": q}

    try:
        search_client = SearchClient(
            endpoint=SEARCH_ENDPOINT,
            index_name=SEARCH_INDEX,
            credential=credential,
        )
        results = list(search_client.search(search_text=q, top=10))
        return {"results": results, "count": len(results), "query": q}
    except Exception as e:
        logger.error(f"Search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/v1/{claim_id}/analyse")
@app.post("/claims/v1/{claim_id}/analyse")
async def analyse_claim(claim_id: str):
    if claim_id not in claims_store:
        raise HTTPException(status_code=404, detail="Claim not found")

    claim = claims_store[claim_id]

    if not OPENAI_ENDPOINT:
        return {
            "claimId": claim_id,
            "analysis": "OpenAI endpoint not configured",
            "riskScore": 0.1,
            "riskBand": "LOW",
            "keyFacts": [],
            "recommendation": "Manual review required",
        }

    try:
        import httpx
        token = credential.get_token("https://cognitiveservices.azure.com/.default").token
        client = AzureOpenAI(
            azure_endpoint=OPENAI_ENDPOINT,
            api_key=token,
            api_version="2024-08-01-preview",
            http_client=httpx.Client(),
        )

        prompt = f"""You are an insurance claims analyst. Analyse this claim and provide:
1. Key facts extracted
2. Risk assessment (LOW/MEDIUM/HIGH) with score 0-1
3. Any fraud indicators
4. Recommendation (APPROVE/INVESTIGATE/REJECT)

Claim details:
- Type: {claim['claimType']}
- Amount: {claim['claimedAmount']} {claim['currency']}
- Incident Date: {claim['incidentDate']}
- Description: {claim['description']}

Respond in JSON format with keys: keyFacts, riskScore, riskBand, fraudIndicators, recommendation, summary"""

        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=500,
        )

        import json
        analysis = json.loads(response.choices[0].message.content)
        analysis["claimId"] = claim_id
        claims_store[claim_id]["status"] = "ANALYSED"
        claims_store[claim_id]["analysis"] = analysis
        return analysis

    except Exception as e:
        logger.error(f"OpenAI error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
