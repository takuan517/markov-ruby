require 'natto'
require 'twitter'
require 'pp'
require 'enumerator'

# ----------------形態素解析
# ----------------辞書的なものの作成
def parse_text(text)
	mecab = Natto::MeCab.new
	text = text.strip
	# 形態素解析したデータを配列に分けて突っ込む
	# 先頭にBEGIN、最後にENDを追加
	data = ["BEGIN","BEGIN"]
	mecab.parse(text) do |a|
		if a.surface != nil
			data << a.surface
		end
	end
	data << "END"
	# p data
	data.each_cons(3).each do |a|
		suffix = a.pop
		prefix = a
		$h[prefix] ||= []
		$h[prefix] << suffix
	end
end

# ----------------マルコフ連鎖
def markov()
	# ランダムインスタンスの生成
	random = Random.new
	# スタートは begin,beginから
	prefix = ["BEGIN","BEGIN"]
	ret = ""
	loop{
		n = $h[prefix].length
		prefix = [prefix[1] , $h[prefix][random.rand(0..n-1)]]
		ret += prefix[0] if prefix[0] != "BEGIN"
		if $h[prefix].last == "END"
			ret += prefix[1]
			break
		end
	}
	p ret
	return ret
end

# ----------------Twitter認証
client = Twitter::REST::Client.new do |config|
	config.consumer_key = "HOGE"
	config.consumer_secret = "HOGE"
	config.access_token = "HOGE"
	config.access_token_secret = "HOGE"
end

# ----------------ツイートの読み込み、テーブル作成
# テーブル用ハッシュ
$h = {}
def collect_with_max_id(collection=[], max_id=nil, &block)
	response = yield(max_id)
	collection += response
	response.empty? ? collection.flatten : collect_with_max_id(collection,response.last.id-1,&block)
end

def client.get_all_tweets(user)
	begin
		collect_with_max_id do |max_id|
			options = {count: 200, include_rts: false, exclude_replies: false}
			options[:max_id] = max_id unless max_id.nil?
			user_timeline(user,options)
		end
	rescue => e
		p e.message
		exit
	end
end

for tweet in client.get_all_tweets("utsubo_21")
	t = tweet.text
	next if t[0,1] == "@" || t.include?("http")
	puts t
	parse_text(t)
end
markov()
