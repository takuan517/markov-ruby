require 'natto'

text = "私の名前はたくみです。"

nm = Natto::MeCab.new

nm.parse(text) do |n|
    puts "#{n.surface}\t#{n.feature}"
end