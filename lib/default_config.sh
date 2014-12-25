# 待ち受けIP 空の場合は全部
listen_ip='127.0.0.1'

# 待ち受けポート
listen_port='43001'

# 名前付きパイプの置き場
fifo_path=/tmp/redmine_mail_receiver

# デバッグモード
debug=true

# 処理後、再待ち受けするか
re_listen=false

# メール内容フォーマット
comment_format='
|_. 送信日 |${date}|
|_. 差出人 |${from}|
|_. 宛先   |${to}|
|_. CC     |${cc}  |
|_. 件名   |${subject}|

本文
<pre>
${body}
</pre>
'

# 送信データフォーマット
send_data_format='<issue>
  <subject>${subject}</subject>
  <description>${description}</description>
</issue>
'
