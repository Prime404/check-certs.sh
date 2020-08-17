#!/bin/bash
# check-certs.sh
# Script that builds on cgmartins work, but with an extensive set of additional features to make it more useful to run as a cronjob.

### Configuration of the script ###
# Connection details for MySQL Database
MYSQL_HOST="localhost"
MYSQL_USER="johndoe"
MYSQL_DB="mydatabase"
MYSQL_PASS="quads"
MYSQL_TABLE="mytable" # Table to load domains from

# Define method to send warnings
WARNING_METHOD="NONE" # NONE, BOTH, WEBHOOK or SMTP

# EMAIL RECIPIENT
EMAIL_RECIPIENT="myemail@domain.com"

function send_webhook {
  # WEBHOOK URL
  WEBHOOK_URL="url.localdomain.com"
  msg_content="Warning: SSL-certificate for $TARGET expires in less than $DAYS days, on $(date -d @$expirationdate '+%Y-%m-%d')" # Content of message that will be sent
  # Use CURL to send webhook
  echo "$msg_content"
  curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"${msg_content}\"}" "$WEBHOOK_URL"
}

function send_smtp {
  # SMTP Credentials for e-mail
  SMTP_HOST="mysmtp.server.com:25"
  SMTP_USER="email@domain.com"
  SMTP_PASS="password"
  SMTP_SENDER="email@domain.com"

  # Generate message
  read -r -d '' mail_content <<- EOM
	Hello,
	This message serves as a notice for that the certificate for $TARGET, expires in less than $DAYS days, on $(date -d @$expirationdate '+%Y-%m-%d').

	These e-mails will be sent out till the certificate is renewed or removed from the datasource.

	Yours truly,
	ssl_alert.sh on behalf of $(whoami)@$(hostname)
	EOM

  # Send e-mail alert using above SMTP details
  sendEmail -t "$EMAIL_RECIPIENT" -u "Certificate expires soon for $TARGET" -f "$SMTP_USER" -s "$SMTP_HOST" -xu "$SMTP_USER" -xp "$SMTP_PASS" -m "$mail_content" > /dev/null
}

# Check if database and table exists before proceeding
if ! mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "use $MYSQL_DB;" ; then
  echo "Error: Database does not exist or wrong connection details." >> /dev/stderr
  exit 1; # Exit script to not cause further errors
elif ! mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" -e "SELECT * from $MYSQL_TABLE;" >/dev/null ; then
  echo "Error: Table does not exist or wrong connection details specificed." >> /dev/stderr
  exit 2; # Exit script to not cause further errors
fi

# Fetch data from database and store it for further use
domains_from_db="$(mysql -B -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" -e "SELECT domain from $MYSQL_TABLE;" | sort -u | sed 's/\*.//')"

# Send an e-mail for every domain that expires within 14 days
for TARGET in $domains_from_db ; do
  if [ "$(nc -z -w5 $TARGET 443 >& /dev/null; echo $?)" == "0" ] ; then
    DAYS=14;
    echo "checking if $TARGET expires in less than $DAYS days";
    expirationdate=$(date -d "$(: | openssl s_client -connect $TARGET:443 -servername $TARGET 2>/dev/null \
                                  | openssl x509 -text \
                                  | grep 'Not After' \
                                  | awk '{print $4,$5,$7}')" '+%s');
    in7days=$(($(date +%s) + (86400*$DAYS)));
    if [ $in7days -gt $expirationdate ] ; then
        echo "KO - Certificate for $TARGET expires in less than $DAYS days, on $(date -d @$expirationdate '+%Y-%m-%d')"
        if [ "$WARNING_METHOD" == "WEBHOOK" ] ; then
          send_webhook
        elif [ "$WARNING_METHOD" == "SMTP" ] ; then
          send_smtp
        elif [ "$WARNING_METHOD" == "BOTH" ] ; then
          send_webhook ; send_smtp
        fi
    else
        echo "OK - Certificate expires on $(date -d @$expirationdate '+%Y-%m-%d')";
    fi
  else
    echo "KO - Domain $TARGET does not resolve to any IP-address, skipping to ensure no errors are reported."
  fi
done
