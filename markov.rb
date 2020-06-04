require 'natto'
require 'twitter'

class TweetBot
  attr_accessor :client
  attr_accessor :screen_name

  public
    def initialize(screen_name)
      @client = Twitter::REST::Client.new do |config|
        config.consumer_key = ENV['CONSUMER_KEY']
        config.consumer_secret = ENV['CONSUMER_SECRET']
        config.access_token = ENV['ACCESS_TOKEN_KEY']
        config.access_token_secret = ENV['ACCESS_TOKEN_SECRET']
      end
  
      @screen_name = screen_name
    end
     
    def post(text = "", twitter_id:nil, status_id:nil)
      if status_id
        rep_text = "@#{twitter_id} #{text}"
        @client.update(rep_text, {:in_reply_to_status_id => status_id})
      else
        @client.update(text)
      end
    end
    
    def get_tweet(count=15, user=@screen_name)
      tweets = []
      
      @client.user_timeline(user, {count: count}).each do |timeline|
        tweet = @client.status(timeline.id)
        # RT(とRTを含むツイート)を除外
        if not (tweet.text.include?("RT"))
          # 泥公式以外からのツイートを除外
          if (tweet.source.include?("TweetDeck") or
            tweet.source.include?("Twitter for Android"))
            tweets.push(tweet2textdata(tweet.text))
          end
        end
      end

      return tweets
    end
    
    def auto_follow()
      begin
        @client.follow(
          get_follower(@screen_name) - get_friend(@screen_name)
        )
      rescue Twitter::Error::Forbidden => error
        # そのまま続ける
      end  
    end
    
  private
    # ===============================================
    # Twitter API
    # ===============================================
    def fav(status_id)
      if status_id
        @client.favorite(status_id)
      end
    end
    
    def retweets(status_id:nil)
      if status_id
        @client.retweet(status_id)
      end
    end
    
    def search(word, count=15)
      tweets = []
      @client.search(word).take(count).each do |tweet|
        tweets.push(tweet.id)
      end
      return tweets
    end
    
    def get_follower(user=@screen_name)
      follower = []
      @client.follower_ids(user).each do |id|
        follower.push(id)
      end
      return follower
    end
    
    def get_friend(user=@screen_name)
      friend = []
      @client.friend_ids(user).each do |id|
        friend.push(id)
      end
      return friend
    end
end

class NattoParser
  attr_accessor :nm
  
  def initialize()
    @nm = Natto::MeCab.new
  end
  
  def parseTextArray(texts)
    words = []
    index = 0

    for text in texts do
      # 単語数を数える
      count_noun = 0
      @nm.parse(text) do |n|
        count_noun += 1
      end

      # 1単語しかなければ以後の処理を行わない
      if count_noun == 1
        break
      end

      words.push(Array[])
      @nm.parse(text) do |n|
        if n.surface != ""
          words[index].push([n.surface, n.posid])
        end
      end
      index += 1
    end

    return words
  end
end

class Marcov
  public
    def marcov(blocks, keyword)
      result = []

      begin
        result = connectBlockBack(
          findBlocks(blocks, keyword), 
          result,
          true
        )
        if result == -1
          raise RuntimeError
        end
      rescue RuntimeError
        retry
      end

      # resultの最後の単語が-1になるまで繰り返す
      while result[result.length-1] != -1 do
        result = connectBlockBack(
          findBlocksBack(blocks, result[result.length-1]), 
          result
        )
      end

      while result[0] != -1 do
        result = connectBlockFront(
          findBlocksFront(blocks, result[0]), 
          result
        )
      end

      return result
    end

    def genMarcovBlock(words)
      array = []

      # 最初と最後は-1にする
      words.unshift(-1)
      words.push(-1)

      # 3単語ずつ配列に格納
      for i in 0..words.length-3
        array.push([words[i], words[i+1], words[i+2]])
      end

      return array
    end

  private
    def findBlocksFront(array, target)
      blocks = []
      for block in array
        if block[2] == target
          blocks.push(block)
        end
      end

      if blocks.empty?
        p array.select {|item| item.include?(target)}
      end

      return blocks
    end

    def findBlocksBack(array, target)
      blocks = []
      for block in array
        if block[0] == target
          blocks.push(block)
        end
      end

      if blocks.empty?
        p array.select {|item| item.include?(target)}
      end
      
      return blocks
    end

    def findBlocks(array, target)
      blocks = []
      for block in array
        if block.include?(target)
          blocks.push(block)
        end
      end
      
      return blocks
    end

    def connectBlockFront(array, dist)
        part_of_dist = []
  
        i = 0
        block = array[rand(array.length)]
  
        for word in block
          if i != 2 or word == -1 # 最後の被り要素を除く
            part_of_dist.unshift(word)
          end
          i += 1
        end
  
        for word in part_of_dist
          dist.unshift(word)
        end
  
        return dist
      end

    def connectBlockBack(array, dist, first_time=false)
      part_of_dist = []

      i = 0

      block = array[rand(array.length)]
      for word in block
        if i != 0 or word == -1 # 先頭の被り要素を除く
          part_of_dist.push(word)
        end
        i += 1
      end

      for word in part_of_dist
        dist.push(word)
      end

      return dist
    end
end

# ===================================================
# 汎用関数
# ===================================================
def generate_text(keyword, bot)
  parser = NattoParser.new
  marcov = Marcov.new

  block = []

  tweet = ""
  
  tweets = bot.get_tweet(200, @screen_name)

  words = parser.parseTextArray(tweets)
  
  # 3単語ブロックをツイートごとの配列に格納
  for word in words
    block.push(marcov.genMarcovBlock(word))
  end

  block = reduce_degree(block)

  # 140字に収まる文章が練成できるまでマルコフ連鎖する
  while tweet.length == 0 or tweet.length > 140 do
    begin
      tweetwords = marcov.marcov(block, keyword)
      if tweetwords == -1
        raise RuntimeError
      end
    rescue RuntimeError
      retry
    end
    tweet = words2str(tweetwords)
  end
  
  return tweet
end

def generate_text_from_json(keyword, dir)
  parser = NattoParser.new
  marcov = Marcov.new

  block = []

  tweet = ""
  
  if dir != ""
    tweets = get_tweets_from_JSON(dir)
  else
    tweets = []
    Dir.glob("data/*"){ |f|
      tweets.push(get_tweets_from_JSON(f))
    }
    tweets = reduce_degree(tweets)
  end

  words = parser.parseTextArray(tweets)
  
  # 3単語ブロックをツイートごとの配列に格納
  for word in words
    block.push(marcov.genMarcovBlock(word))
  end

  block = reduce_degree(block)

  # 140字に収まる文章が練成できるまでマルコフ連鎖する
  while tweet.length == 0 or tweet.length > 140 do
    begin
      tweetwords = marcov.marcov(block, keyword)
      if tweetwords == -1
        raise RuntimeError
      end
    rescue RuntimeError
      retry
    end
    tweet = words2str(tweetwords)
  end
  
  return tweet
end

def get_tweets_from_JSON(filename)
  data = nil

  File.open(filename) do |f|
    data = JSON.load(f)
  end

  tweets = []

  for d in data do
    if d["user"]["screen_name"] == "hsm_hx"
      if d["retweeted_status"] == nil
        tweets.push(tweet2textdata(d["text"]))
      end
    end
  end

  return tweets
end

def words2str(words)
  str = ""
  for word in words do
    if word != -1
      str += word[0]
    end
  end
  return str
end

def reduce_degree(array)
  result = []

  array.each do |a|
    a.each do |v|
      result.push(v)
    end
  end
  
  return result
end

def tweet2textdata(text)
  replypattern = /@[\w]+/

  text = text.gsub(replypattern, '')

  textURI = URI.extract(text)

  for uri in textURI do
    text = text.gsub(uri, '')
  end 

  return text
end