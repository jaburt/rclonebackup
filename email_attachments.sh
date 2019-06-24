#!/bin/bash

# script to send zero or more attachments with mime-encoding from any email address to any email address.

# based on: 
# http://backreference.org/2013/05/22/send-email-with-attachments-from-script-or-command-line/

if [ "$#" -lt 4 ]; then
  echo "Usage: ${0} from@email to@email \"subject of email\" \"body of email\" [attachment1 [...]]"
  exit 
fi 

from="$1"
to="$2"
subject="$3"
boundary="ZZ_/afg6432dfgkl.94531q"
body="$4"
declare -a attachments

shift 4

attachments=($@)

get_mimetype(){
  # warning: assumes that the passed file exists
  file --mime-type "$1" | sed 's/.*: //'
}

# Build headers
{

printf '%s\n' "From: $from 
To: $to
Subject: $subject
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$boundary\"

--${boundary} 
Content-Type: text/plain; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline 

$body
"

# now loop over the attachments, guess the type 
# and produce the corresponding part, encoded base64
for file in "${attachments[@]}"; do

  [ ! -f "$file" ] && echo "Warning: attachment $file not found, skipping" >&2 && continue

  mimetype=$(get_mimetype "$file")

  printf '%s\n' "--${boundary}
Content-Type: $mimetype
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=\"$file\"
"

  base64 "$file"
  echo
done

# print last boundary with closing --
printf '%s\n' "--${boundary}--"

} | sendmail -t -oi # one may also use -f here to set the envelope-from
