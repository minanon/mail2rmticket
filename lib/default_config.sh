# 待ち受けIP 空の場合は全部
listen_ip='127.0.0.1'

# 待ち受けポート
listen_port='43001'

# 名前付きパイプの置き場
fifo_path=/tmp/redmine_mail_receiver

# デバッグモード
debug=false

# 処理後、再待ち受けするか
re_listen=false

# メッセージ言語
message_lang='ja'

# メール内容フォーマット
comment_format_en='
|_. Send Date |${date}|
|_. Sender |${from}|
|_. Receiver   |${to}|
|_. CC     |${cc}  |
|_. Subject   |${subject}|

Message
&lt;pre&gt;
${body}
&lt;/pre&gt;
'

comment_format_ja='
|_. 送信日 |${date}|
|_. 差出人 |${from}|
|_. 宛先   |${to}|
|_. CC     |${cc}  |
|_. 件名   |${subject}|

本文
&lt;pre&gt;
${body}
&lt;/pre&gt;
'

# 送信データフォーマット
send_data_format_new='<issue>
  <subject>${subject}</subject>
  <description>${description}</description>
</issue>
'

send_data_format_edit='<issue>
  <subject>${subject}</subject>
  <notes>${description}</notes>
</issue>
'
