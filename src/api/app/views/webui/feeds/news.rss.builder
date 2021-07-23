xml.rss version: '2.0' do
  xml.channel do
    xml.title "#{@configuration['title']} News"
    xml.description 'Recent news'
    xml.link url_for only_path: false, controller: 'main', action: 'index'

    @news.each do |message|
      xml.item do
        xml.title message.message
        xml.pubDate message.created_at
        xml.author message.user
        xml.link url_for only_path: false, controller: 'main', action: 'index'
      end
    end
  end
end
