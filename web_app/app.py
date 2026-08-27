import os
import base64
import json
import random
from datetime import datetime, timezone
from functools import wraps

import boto3
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify

app = Flask(__name__)

# For test
app.secret_key = "artisanapp0101"  # For Test. In production, app will be well written.

REGION = "eu-north-1"


# Extract useful data from AWS SSM Parameter Store
def get_ssm_parameter(param_name, with_decryption=True):
    try:
        ssm = boto3.client("ssm", region_name = REGION)
        response = ssm.get_parameter(Name=param_name, WithDecryption=with_decryption)
        return response["Parameter"]["Value"]
    except Exception as e:
        print(f"Warning: Unable to fetch {param_name} from SSM - {e}")
        return None


S3_BUCKET_NAME = get_ssm_parameter("s3_bucket_name")

DYNAMO_TABLE = get_ssm_parameter("dynamodb_name")

# Cognito Hosted UI domain – where Cognito’s login/signup pages live.
APP_DOMAIN = get_ssm_parameter("cognito_domain")
COGNITO_DOMAIN = f"{APP_DOMAIN}.auth.{REGION}.amazoncognito.com"

COGNITO_CLIENT_ID = get_ssm_parameter("cognito_client_id")

# My app’s public URL – where my Flask app is served.
APP_PUBLIC_URL = "https://www.builtbyedunoh.com"   # no trailing slash


@app.route("/cognito-login")
def cognito_login():
    # Build the Cognito authorize URL (same as ALB would use)
    cognito_authorize = (
        f"https://{COGNITO_DOMAIN}/oauth2/authorize"
        f"?client_id={COGNITO_CLIENT_ID}"
        f"&response_type=code"
        f"&scope=openid+email+profile"
        f"&redirect_uri={APP_PUBLIC_URL}/oauth2/idpresponse"   # ALB callback
    )
    return redirect(cognito_authorize)


def get_authenticated_user():
    data_header = request.headers.get("X-Amzn-Oidc-Data")
    if data_header:
        try:
            claims = json.loads(base64.b64decode(data_header).decode("utf-8"))
            return {
                "username": claims.get("cognito:username") or claims.get("email", "unknown"),
                "email": claims.get("email", ""),
                "groups": claims.get("cognito:groups", []),
            }
        except Exception:
            pass
    return None


def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        user = get_authenticated_user()
        if not user:
            flash("Please log in", "error")
            return redirect(url_for("cognito_login")) 
        return f(user, *args, **kwargs)
    return wrapper


artisan_categories = {
    "Electrical": ["Bright Sparks Ltd", "PowerFix Nigeria"],
    "Plumbing": ["PipeMasters", "FlowFix Nigeria"],
    "Carpentry": ["WoodCraft NG", "FineFinish Carpentry"],
    "Painting": ["ColorSplash NG", "ProBrush Painters"],
    "HVAC": ["CoolAir Systems", "ChillPro NG"],
}
cities = ["Uyo", "Lagos", "Abuja", "Port Harcourt"]


def generate_fixed_artisans():
    artisans = []
    for category, names in artisan_categories.items():
        for name in names:
            artisans.append({
                "name": name,
                "category": category,
                "address": f"{random.randint(1, 200)} {random.choice(['Main St', 'Broadway'])}, {random.choice(cities)}",
            })
    return artisans


@app.route("/health")
def health_check():
    return jsonify({"status": "healthy"}), 200


@app.route("/")
def landing():
    # Build the Cognito sign-up URL. This is a direct link to Cognito’s sign-up page.
    # After sign-up, Cognito redirects the user back to the landing page.

    # client_id must be cognito App Client ID.
    # response_type=code tells Cognito to use the Authorization Code grant.
    # scope=openid+email+profile requests the OIDC scopes so that Cognito returns an ID token with email and profile claims.
    # redirect_uri is where Cognito sends the user after successful sign-up. It must be exactly listed in the Cognito App Client → Hosted UI → Allowed callback URLs.
    # In Cognito settings, I added:
    # callback_urls = [
    #     "https://www.builtbyedunoh.com/oauth2/idpresponse",   # for ALB authentication
    #     "https://www.builtbyedunoh.com/"                      # for direct signup redirect
    # ]

    signup_url = (
        f"https://{COGNITO_DOMAIN}/signup"
        f"?client_id={COGNITO_CLIENT_ID}"
        f"&response_type=code"
        f"&scope=openid+email+profile"
        f"&redirect_uri={APP_PUBLIC_URL}/home"
    )

    return render_template("landing.html", signup_url=signup_url)


@app.route("/home")
@login_required
def home(user):
    email = user["email"] or user["username"]
    artisans = generate_fixed_artisans()

    category_counts = {}
    for artisan in artisans:
        category_counts[artisan["category"]] = category_counts.get(artisan["category"], 0) + 1

    return render_template(
        "home.html",
        username=email.split("@")[0],
        email=email,
        artisans=artisans,
        category_counts=category_counts,
    )


@app.route("/submit_request", methods=["POST"])
@login_required
def submit_request(user):
    email = user["email"] or user["username"]
    address = request.form.get("address")
    contact_number = request.form.get("contact_number")
    service_title = request.form.get("service_title")
    artisan_name = request.form.get("artisan_name")
    description = request.form.get("description")
    file = request.files.get("file")

    if not all([email, service_title, artisan_name, address, description]):
        flash("Please fill in all required fields.", "error")
        return redirect(url_for("home"))

    try:
        s3_key = None
        if file:
            from werkzeug.utils import secure_filename
            s3 = boto3.client("s3", region_name=REGION)

            filename = secure_filename(file.filename)

            s3.upload_fileobj(file, S3_BUCKET_NAME, filename)

            s3_key = filename


        dynamodb = boto3.resource("dynamodb", region_name=REGION)

        table = dynamodb.Table(DYNAMO_TABLE)

        table.put_item(Item={
            "username": user["username"],
            "request_date": datetime.now(timezone.utc).isoformat(),
            "user_email": email,
            "user_address": address,
            "user_contact_number": contact_number,
            "service_description": description,
            "image_s3_key": s3_key,
            "requested_service_title": service_title,
            "requested_artisan_name": artisan_name,
        })

        flash("Request submitted successfully!", "success")
    except Exception as e:
        print(f"Error: {e}")
        flash("Failed to submit request.", "error")

    return redirect(url_for("home"))




# If I redirect straight to / (landing page) without logging out of Cognito, the user would still have a valid Cognito session. 
# The next time they click Sign In, the ALB might skip the login page and send them straight to /home because they’re still authenticated. That would break the expected logout behavior.
# Ensure the redirect URIs (Example: https://www.builtbyedunoh.com/) are registered in Cognito app client settings under Allowed callback URLs and Allowed logout URLs.
@app.route("/logout")
def logout():
    cognito_logout = (
        f"https://{COGNITO_DOMAIN}/logout"
        f"?client_id={COGNITO_CLIENT_ID}"
        f"&logout_uri={APP_PUBLIC_URL}/home"
    )
    resp = redirect(cognito_logout)
    resp.delete_cookie("AWSELBAuthSessionCookie")
    return resp


if __name__ == "__main__":
    app.run(debug=True)
