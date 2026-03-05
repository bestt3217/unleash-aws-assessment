import asyncio
import time
import boto3
import httpx
import os

REGION = "us-east-1"
CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]
USERNAME = os.environ["COGNITO_USERNAME"]
PASSWORD = os.environ["COGNITO_PASSWORD"]

API_US = os.environ["API_URL_US"]
API_EU = os.environ["API_URL_EU"]

def get_token():
    client = boto3.client("cognito-idp", region_name=REGION)

    resp = client.initiate_auth(
        ClientId=CLIENT_ID,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={
            "USERNAME": USERNAME,
            "PASSWORD": PASSWORD,
        },
    )

    return resp["AuthenticationResult"]["AccessToken"]


async def call_endpoint(client, url, token):
    headers = {"Authorization": f"Bearer {token}"}

    start = time.perf_counter()

    resp = await client.get(url, headers=headers)

    latency = (time.perf_counter() - start) * 1000

    return {
        "url": url,
        "status": resp.status_code,
        "body": resp.text,
        "latency_ms": latency,
    }

async def main():
    token = get_token()

    async with httpx.AsyncClient() as client:

        greet_us = call_endpoint(client, f"{API_US}/greet", token)
        greet_eu = call_endpoint(client, f"{API_EU}/greet", token)

        dispatch_us = client.post(
            f"{API_US}/dispatch",
            headers={"Authorization": f"Bearer {token}"}
        )

        dispatch_eu = client.post(
            f"{API_EU}/dispatch",
            headers={"Authorization": f"Bearer {token}"}
        )

        results = await asyncio.gather(
            greet_us,
            greet_eu,
            dispatch_us,
            dispatch_eu,
        )

    print("\nResults:\n")

    for r in results:
        if isinstance(r, dict):
            print(
                f"{r['url']} -> {r['status']} "
                f"({r['latency_ms']:.2f} ms) {r['body']}"
            )
        else:
            print(f"Dispatch -> {r.status_code} {r.text}")


if __name__ == "__main__":
    asyncio.run(main())