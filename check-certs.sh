#!/bin/bash
# check-certs.sh
# Script that builds on cgmartins work, but with an extensive set of additional features to make it more useful to run as a cronjob.

# Here we load the .env file containing the settings
if [ -f .env ] ; then
  export $(cat .env | sed 's/#.*//g' | xargs)
else
  echo "Error: The .env file could not be found, please ensure the file exists and is readable by the user." >> /dev/stderr
  exit 1; # Exit script to not cause further errors
fi

function send_webhook {
  msg_content="Warning: SSL-certificate for $TARGET expires in less than $DAYS days, on $(date -d @$expirationdate '+%Y-%m-%d')" # Content of message that will be sent
  # Use CURL to send webhook
  curl -H "Content-Type: application/json" -X POST -d "{\"text\": \"${msg_content}\"}" "$WEBHOOK_URL"
}

function send_smtp {
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
  exit 2; # Exit script to not cause further errors
elif ! mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" -e "SELECT * from \`${MYSQL_TABLE}\`;" >/dev/null ; then
  echo "Error: Table does not exist or wrong connection details specificed." >> /dev/stderr
  exit 3; # Exit script to not cause further errors
fi

# Fetch data from database and store it for further use
domains_from_db="$(mysql -N -B -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" -e "SELECT \`${MYSQL_COL}\` from \`${MYSQL_TABLE}\`;" | sort -u | sed 's/\*.//')"

# Send an e-mail for every domain that expires within 14 days
for TARGET in $domains_from_db ; do
  echo $TARGET
  if [ "$(nc -z -w2 $TARGET 443 >& /dev/null; echo $?)" == "0" ] ; then
    DAYS=14;
    echo "checking if $TARGET expires in less than $DAYS days";
    expirationdate=$(date -d "$(: | timeout --preserve-status 60 openssl s_client -connect $TARGET:443 -servername $TARGET 2>/dev/null \
                                  | openssl x509 -text \
                                  | grep 'Not After' \
                                  | awk '{print $4,$5,$7}')" '+%s');
    in7days=$(($(date +%s) + (86400*$DAYS)));
    if [ $in7days -gt $expirationdate ] ; then
        echo "KO - Certificate for $TARGET expires in less than $DAYS days, on $(date -d @$expirationdate '+%Y-%m-%d')"
        if [ "$WARNING_METHOD" == "WEBHOOK" ] ; then
          echo Sending webhook
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
