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
app.secret_key = "artisanapp0101"

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

APP_DOMAIN = get_ssm_parameter("cognito_domain")
COGNITO_DOMAIN = f"{APP_DOMAIN}.auth.{REGION}.amazoncognito.com"

COGNITO_CLIENT_ID = get_ssm_parameter("cognito_user_pool_id")

APP_DOMAIN = "https://www.builtbyedunoh.com"   # no trailing slash


def get_authenticated_user():
    identity = request.headers.get("X-Amzn-Oidc-Identity")
    data_header = request.headers.get("X-Amzn-Oidc-Data")

    if not identity or not data_header:
        return None

    try:
        claims = json.loads(base64.b64decode(data_header).decode("utf-8"))
    except Exception:
        return None

    return {
        "username": claims.get("cognito:username", identity),
        "email": claims.get("email", ""),
        "groups": claims.get("cognito:groups", []),
    }


def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        user = get_authenticated_user()
        if not user:
            flash("Please log in", "error")
            return redirect(url_for("landing"))
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
    # Build the Cognito sign-up URL.
    # After sign-up, Cognito redirects the user back to the landing page.
    signup_url = (
        f"https://{COGNITO_DOMAIN}/signup"
        f"?client_id={COGNITO_CLIENT_ID}"
        f"&response_type=code"
        f"&scope=openid+email+profile"
        f"&redirect_uri={APP_DOMAIN}/"
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


@app.route("/logout")
def logout():

    # If I redirect straight to / (landing page) without logging out of Cognito, the user would still have a valid Cognito session. 
    # The next time they click Sign In, the ALB might skip the login page and send them straight to /home because they’re still authenticated. That would break the expected logout behavior.
    cognito_logout = (
        f"https://{COGNITO_DOMAIN}/logout"
        f"?client_id={COGNITO_CLIENT_ID}"
        f"&logout_uri={APP_DOMAIN}/"
    )

    # Redirect to Cognito logout, but also clear the ALB session cookie.
    resp = redirect(cognito_logout)
    resp.delete_cookie("AWSELBAuthSessionCookie")
    return resp


if __name__ == "__main__":
    app.run(debug=True)
















# 1. User visits your domain (e.g., https://www.builtbyedunoh.com/)
# They see the landing page (landing.html).

# The landing page has two buttons:

# Create Account

# Sign In

# No login form is shown here. The Flask app does not ask for credentials.

# 2. If the user clicks Sign In
# The button is a simple link to /home.

# The browser requests /home.

# Your ALB is configured with Cognito authentication for the /home path.

# Since the user is not logged in yet, the ALB redirects the browser to Cognito’s hosted login page.

# The browser now displays Cognito’s login form (username/password).

# User enters their credentials.

# Cognito verifies them.

# Cognito redirects the browser back to your ALB, which then sends the user to /home with the authentication headers.

# Your Flask app reads the headers and shows the home.html page.

# So the user never sees a login page from your Flask app. Login is entirely handled by Cognito.

# 3. If the user clicks Create Account (new user)
# The button is a direct link to Cognito’s sign-up page (signup_url built in Flask).

# The browser goes to Cognito’s sign-up form.

# User fills in their details and submits.

# Cognito registers the user and (depending on your settings) may send a verification email.

# After sign-up, Cognito redirects the browser back to the URL you provided as redirect_uri. In your Flask code, this is set to https://www.builtbyedunoh.com/ (the landing page).

# The user is now back on the landing page.

# They then click Sign In and go through the normal login flow (step 2).

# This matches exactly what you described:

# “Once the user signs up, it takes the user back to the landing page and asks the user to sign in.”

# 4. Logout
# On the home.html page, there is a Logout link.

# Clicking it calls /logout in Flask.

# That route redirects to Cognito’s logout endpoint and clears the ALB session cookie.

# The user is returned to the landing page (https://www.builtbyedunoh.com/).

# They are now logged out and see the two buttons again.

# Why is it confusing?
# Because the Sign In button does not look like a login form; it just points to /home. But the ALB automatically redirects to Cognito, so the user never sees a separate login page from your app. The login form they see is Cognito’s, not Flask’s.

# Diagram
# text
# Landing page (/)
#   ├── [Create Account] → Cognito signup → redirect back to landing
#   └── [Sign In] → /home → ALB redirects to Cognito login → back to /home
# Key Configuration Checklist
# Make sure in Cognito app client you have:

# Callback URL for ALB login: https://www.builtbyedunoh.com/oauth2/idpresponse

# Callback URL for signup direct link: https://www.builtbyedunoh.com/ (or whatever APP_DOMAIN/ is in Flask)

# Logout URL: https://www.builtbyedunoh.com/

# And in your ALB ingress, the auth settings are correctly applied to / or /home (or both) as needed.

# That’s the whole flow. No additional pages in your Flask app are needed.