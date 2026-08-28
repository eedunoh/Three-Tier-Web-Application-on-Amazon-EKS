# What I want:
# All users (admins and regular users) can access the Flask app via / or /app.
# Only admins can access Grafana via /grafana.
# Both use the same ALB.


# Setup:
# Cognito handles login (the hosted UI).
# ALB authenticates the user via Cognito.
# ALB passes user info as HTTP headers to your app and Grafana.
# Grafana checks if the user is in the admin group; if not, it denies access.


# Cognito headers:

# 1. x-amzn-oidc-identity: the user's Cognito sub/unique identity;
  # X-Amzn-Oidc-Identity: 9f3c2b7e-1234-4567-89ab-123456789abc


# 2. x-amzn-oidc-data: signed JWT containing the user's identity claims:
  # {
  #   "sub":"abc123",
  #   "email":"user@example.com",
  #   "cognito:groups":["admin"]
  # }


# 3. x-amzn-oidc-accesstoken: OAuth access token obtained during authentication:
  # {
  #   "sub": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  #   "iss": "https://cognito-idp.eu-north-1.amazonaws.com/eu-north-1_AbC123XyZ",
  #   "version": 2,
  #   "client_id": "your-cognito-app-client-id",
  #   "origin_jti": "...",
  #   "token_use": "access",
  #   "scope": "openid email profile",
  #   "auth_time": 1700000000,
  #   "exp": 1700003600,
  #   "iat": 1700000000,
  #   "jti": "...",
  #   "username": "johndoe",
  #   "cognito:groups": ["admin"],
  #   "email": "john@example.com"
  # }


# Cognito User Pool: A User Pool is your user database
resource "aws_cognito_user_pool" "my_user_pool" {
  name = var.user_pool_name

  deletion_protection = "INACTIVE"
  auto_verified_attributes = ["email"]
  mfa_configuration = "OFF"

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                   = true
    require_symbols                   = true
    require_uppercase                 = true
    password_history_size             = 0
    temporary_password_validity_days  = 7
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true

    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # This block configures Amazon Cognito to send emails using its built-in, shared email service rather than your own Amazon SES account.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option   = "CONFIRM_WITH_LINK"
    email_message_by_link  = "Please click the link below to verify your email address. {##Verify Email##}. Stay Informed! Thanks for joining!"
    email_subject_by_link  = "Your app verification link"
  }

}

# Configure Cognito Domain
# Cognito Hosted UI domain – where Cognito’s login/signup pages live.
# Cognito domain = the login endpoint Cognito provides, e.g. https://eks-app.auth.eu-north-1.amazoncognito.com. Users are sent here to log in.
resource "aws_cognito_user_pool_domain" "my_domain" {
  domain       = "eks-app"                                     # The Cognito domain is needed for OAuth token exchange between the app and cognito. It works behind the scene.
  user_pool_id = aws_cognito_user_pool.my_user_pool.id
}


# Cognito supports adding/removing users from groups.
# If you create a Cognito user and do nothing else, the user is simply in no Cognito group. Groups are not automatically assigned. 
# You need to explicitly add the user to a roup, e.g. through a post-confirmation Lambda or your application/admin process.
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.my_user_pool.id
  description  = "Application administrators"
}

resource "aws_cognito_user_group" "users" {
  name         = "users"
  user_pool_id = aws_cognito_user_pool.my_user_pool.id
  description  = "Regular application users"
}




# UserPool Client is the application that connects to the userpool database.
resource "aws_cognito_user_pool_client" "my_user_pool_client" {
  name         = var.user_pool_client_name
  user_pool_id = aws_cognito_user_pool.my_user_pool.id

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 5

# generate app client secret
  generate_secret     = true      

  allowed_oauth_flows                   = ["code"]
  allowed_oauth_flows_user_pool_client  = true
  allowed_oauth_scopes                  = ["email", "openid", "phone"]

  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  supported_identity_providers = ["COGNITO"]
  

  # The callback URL is the return address Cognito uses after authentication. Its where Cognito redirects users and delivers OAuth tokens after any successful login. 
  # It tells Cognito, “The ALB is handling this login; send the authentication response back to this ALB endpoint.” For ALB + Cognito, that endpoint is https://www.builtbyedunoh.com/oauth2/idpresponse.
  # The user does not visit /oauth2/idpresponse as an application page, and you don't route it to Flask or Grafana. The ALB handles it internally, completes the authentication, and then continues the user's original request to / or /grafana.
  callback_urls = [
    "https://www.builtbyedunoh.com/oauth2/idpresponse",       # for ALB authentication
    "https://www.builtbyedunoh.com/home"                          # for direct signup redirect
  ]


  # The logout_urls list is required because your Flask /logout route redirects the browser to Cognito's logout endpoint with a logout_uri parameter.
  # https://www.builtbyedunoh.com/ is where I want the user to land after logout. I must explicitly tell Cognito: “This URL is allowed for logout redirects.”
  logout_urls = [
    "https://www.builtbyedunoh.com/"
  ]
}



output "user_pool_id" {
  value = aws_cognito_user_pool.my_user_pool.id
}


output "user_pool_arn" {
  value = aws_cognito_user_pool.my_user_pool.arn
}


output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.my_user_pool_client.id
}


output "user_pool_client_secret" {
  value = aws_cognito_user_pool_client.my_user_pool_client.client_secret
  sensitive = true
}


output "user_pool_domain" {
  value = aws_cognito_user_pool_domain.my_domain.domain
}