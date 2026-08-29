from flask import Flask, render_template, request, redirect, url_for, session, jsonify, flash
import os, random, logging
from flask_session import Session
from config import Config
import boto3
from utils import authenticate_user, register_user  # Cognito integration functions
from datetime import datetime, timezone

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ensure Config is initialized before creating the app
Config.initialize()

app = Flask(__name__)
app.secret_key = Config.APP_SECRET_KEY
app.config.from_object(Config)



# Secure session settings
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SECURE"] = False  # Change to True in production (HTTPS)
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"


# Health check endpoint for ALB
@app.route("/health")
def health_check():
    return jsonify({"status": "healthy"}), 200  # ALB expects HTTP 200


# Artisan categories and cities
artisan_categories = {
    "Electrical": ["Bright Sparks Ltd", "PowerFix Nigeria", "LightWave Solutions", "ElectroPro NG", "WireMasters NG", "AmpedUp NG"],
    "Plumbing": ["PipeMasters", "FlowFix Nigeria", "BlueDrop Plumbing", "LeakStop NG", "DrainPro NG", "SwiftPipe Services", "PlumbKing NG"],
    "Carpentry": ["WoodCraft NG", "FineFinish Carpentry", "Oak & Nails", "UrbanWood Works", "NailIt Pro", "CarveCraft NG", "EliteWood Masters", "CustomJoinery NG"],
    "Painting": ["ColorSplash NG", "ProBrush Painters", "FreshCoat Nigeria", "ElitePainters NG", "PaintMaster NG"],
    "HVAC": ["CoolAir Systems", "ChillPro NG", "AirFix Solutions"]
}
cities = ["Uyo", "Lagos", "Ibadan", "Abuja", "Port Harcourt", "Enugu", "Kano"]

def generate_fixed_artisans():
    artisans = []
    for category, names in artisan_categories.items():
        num_to_pick = min(10, len(names))
        selected_names = names[:num_to_pick]
        for name in selected_names:
            artisans.append({
                "name": name,
                "category": category,
                "address": f"{random.randint(1, 200)} {random.choice(['Main St', 'Broadway', 'Market Rd', 'Church St'])}, {random.choice(cities)}",
            })
    return artisans

@app.route("/")
def landing():
    return render_template("landing.html")


@app.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        # Check if the request is JSON (from fetch) or form data
        if request.is_json:
            data = request.get_json()
            username = data.get("username")
            email = data.get("email")
            password = data.get("password")
        else:
            username = request.form.get("username")
            email = request.form.get("email")
            password = request.form.get("password")

        if not username or not email or not password:
            if request.is_json:
                return jsonify({'success': False, 'message': 'All fields are required'}), 400
            else:
                flash("All fields are required", "error")
                return redirect(url_for("signup"))

        if register_user(username, password, email):
            logger.info(f"User '{username}' registered successfully.")
            if request.is_json:
                return jsonify({'success': True, 'message': 'Signup successful! Check your email for verification.'})
            else:
                flash("Signup successful! Check your email for verification.", "success")
                return redirect(url_for("login"))
        else:
            if request.is_json:
                return jsonify({'success': False, 'message': 'Signup failed. User may already exist.'}), 400
            else:
                flash("Signup failed. User may already exist.", "error")
    
    return render_template("signup.html")



@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")

        if not username or not password:
            flash("Username and password are required.", "error")
            return redirect(url_for("login"))

        if authenticate_user(username, password):
            session["user"] = username
            session.modified = True
            flash("Login successful!", "success")
            return redirect(url_for("home"))

        flash("Invalid credentials. Please try again.", "error")

    return render_template("login.html")



@app.route("/home")
def home():
    if "user" not in session:
        return redirect(url_for("login"))

    email = session["user"]
    artisans = generate_fixed_artisans()

    # Count per category
    category_counts = {}
    for artisan in artisans:
        category_counts[artisan["category"]] = category_counts.get(artisan["category"], 0) + 1

    return render_template(
        "home.html",
        username=email.split("@")[0],  # Example: derive name from email
        email=email,
        artisans=artisans,
        category_counts=category_counts
    )

@app.route("/submit_request", methods=["POST"])
def submit_request():

    # Log immediately when the route is hit
    print("📥 Frontend request reached /submit_request route!")
    logger.info("📥 Frontend request reached /submit_request route!")

    if "user" not in session:
        flash("You need to be logged in to submit a request.", "error")
        return redirect(url_for("home"))
    
    print(f"📨 Form data received: {dict(request.form)}")
    print(f"📁 Files received: {dict(request.files)}")
    print(f"📦 File object: {request.files.get('file')}")

    username = session["user"]  # Always trust Cognito session, not form input
    email = request.form.get("email")
    address = request.form.get('address')
    contact_number = request.form.get('contact_number')
    service_title = request.form.get('service_title')
    artisan_name = request.form.get('artisan_name')
    description = request.form.get('description')
    file = request.files.get('file')

    # --- Add validation for required fields ---
    if not all([email, service_title, artisan_name, address, description]):
        flash("Please fill in all required fields: email, service title, artisan, address, and description.", "error")
        return redirect(url_for("home"))

    logger.info(f"Request from {username} ({email}): {service_title} with {artisan_name}, Address: {address}, Contact: {contact_number}, Description: {description}")

    # --- Upload file to S3 ---
    try:
        s3_key = None
        if file:
            from werkzeug.utils import secure_filename
            s3_client = boto3.client("s3", region_name=Config.REGION)

            filename = secure_filename(file.filename)

            logger.info(f"Attempting to upload {filename} to S3 bucket {Config.S3_BUCKET_NAME}")

            s3_client.upload_fileobj(file, Config.S3_BUCKET_NAME, filename)
            s3_key = filename

            logger.info(f"Successfully uploaded {filename} to S3")


        # --- Save request metadata to DynamoDB ---
        dynamodb = boto3.resource("dynamodb", region_name=Config.REGION)
        table = dynamodb.Table(Config.DYNAMO_NAME)
        
        logger.info(f"Attempting to save to DynamoDB table {Config.DYNAMO_NAME}")


        table.put_item(Item={
            "username": username,
            "request_date": datetime.now(timezone.utc).isoformat(),
            "user_email": email,
            "user_address": address,
            "user_contact_number": contact_number,
            "service_description": description,
            "image_s3_key": s3_key,
            "requested_service_title": service_title,
            "requested_artisan_name": artisan_name
        })

        logger.info("Successfully saved to DynamoDB")


        flash("Request submitted successfully!", "success")
        return redirect(url_for("home"))
        
    except Exception as e:
        
        # CAPTURE THE ACTUAL ERROR!
        logger.error(f"AWS Operation Failed: {str(e)}")
        logger.error(f"Error type: {type(e).__name__}")
        
        # Log stack trace for better debugging
        import traceback
        logger.error(f"Stack trace: {traceback.format_exc()}")
        
        flash("Failed to submit request. Please try again.", "error")
        return redirect(url_for("home"))

@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "success")
    return redirect(url_for("landing"))

if __name__ == "__main__":
    app.run(debug=True)