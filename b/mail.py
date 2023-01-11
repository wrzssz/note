#!/usr/bin/env python3
# 发邮件的小脚本
# python3 ./mail.py -s "$(TZ=CST-8 date)" -b 'This is mail body.'

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('-s', '--subject', type=str, default='default subject')
parser.add_argument('-b', '--body', type=str, default='default body')
args = parser.parse_args()

import smtplib
sender = 'foo@gmail.com'
receiver = 'bar@outlook.com'
smtp = smtplib.SMTP_SSL('smtp.gmail.com', 465)
smtp.login(user=sender, password='ppaasswwoorrdd')

from email.mime.text import MIMEText
from email.header import Header
message = MIMEText(args.body, 'plain', 'utf-8')
message['From'] = Header(sender, 'utf-8')
message['To'] = Header(receiver, 'utf-8')
message['Subject'] = Header(args.subject, 'utf-8')

smtp.sendmail(from_addr=sender, to_addrs=receiver, msg=message.as_string())