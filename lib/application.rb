require 'hotcocoa'
require 'json'

class Postie
  include HotCocoa
  
  POSTRANK_URL_BASE = "http://api.postrank.com/v2"
  APPKEY = "appkey=Postie"
  
  def start
    application(:name => "Postie") do |app|
      app.delegate = self
      window(:size => [640, 480], :center => true, :title => "Postie", :view => :nolayout) do |win|
        win.will_close { exit }

        win.view = layout_view(:layout => {:expand => [:width, :height],
                                           :padding => 0}) do |vert|
          vert << layout_view(:size => [0, 40], :mode => :horizontal,
                              :layout => {:padding => 0, :start => false, :expand => [:width]}) do |horiz|
            horiz << label(:text => "Feed", :layout => {:align => :center})
            horiz << @feed_field = text_field(:text => 'everburning.com', :layout => {:expand => [:width]})
            horiz << button(:title => 'go', :layout => {:align => :center}) do |b|
              b.on_action do
                load_feed

                @timer.invalidate unless @timer.nil?
                @timer = NSTimer.scheduledTimerWithTimeInterval(30, target:self,
                                                                selector:"refresh".to_sym,
                                                                userInfo:nil, repeats:true)
              end
            end
          end

          vert << scroll_view(:layout => {:expand => [:width, :height]}, :autohide_scrollers => true) do |scroll|
            scroll << @table = table_view(:columns => [column(:id => :postrank, :title => '',
                                                              :data_cell => PostRankCell.new,
                                                              :max_width => 34, :min_width => 34),
                                                       column(:id => :data, :title => '',
                                                               :data_cell => PostCell.new)],
                                          :data => [],
                                          :grid_style => :horizontal,
                                          :alternating_row_background_colors => true) do |table|
               table.setRowHeight(PostCell::ROW_HEIGHT)
               table.setDelegate(self)
               table.setDoubleAction(:table_clicked)
            end
          end
        end
      end
    end
  end

  def refresh
    load_feed
  end

  def table_clicked
    url = NSURL.URLWithString(@table.data_source.data[@table.clickedRow][:data][:link])
    NSWorkspace.sharedWorkspace.openURL(url)
  end
  
  def tableView(table, heightOfRow:row)
    metrics = @table.data_source.data[row][:data][:metrics].keys.length
    
    num_rows = (metrics / PostCell::NUM_METRICS_PER_ROW) + 1
    num_rows -= 1 if metrics > 0 && (metrics % PostCell::NUM_METRICS_PER_ROW) == 0
    num_rows = 0 if metrics == 0

    num_rows * PostCell::ROW_HEIGHT + PostCell::ROW_HEIGHT  # 2nd row height for the title
  end
  
  def load_feed
    @table.data = []

    str = @feed_field.stringValue
    unless str.nil? || str =~ /^\s*$/
      fetch_feed(str)
    end
  end
  
  def fetch_feed(url)
    DataRequest.new.get("#{POSTRANK_URL_BASE}/feed/info?id=#{url}&#{APPKEY}") do |data|
      feed_info = JSON.parse(data)
      unless feed_info.has_key?('error')
        DataRequest.new.get("#{POSTRANK_URL_BASE}/feed/#{feed_info['id']}?#{APPKEY}") do |data|
          feed = JSON.parse(data)
          feed['items'].each do |item|
            post_data = {:title => item['title'], :link => item['original_link'], :metrics => {}}
            @table.data_source.data << {:data => post_data,
                                       :postrank => {:value => item['postrank'],
                                                     :color => item['postrank_color']}}
            DataRequest.new.get("#{POSTRANK_URL_BASE}/entry/#{item['id']}/metrics?#{APPKEY}") do |data|
              metrics = JSON.parse(data)
              metrics[item['id']].each_pair do |key, value|
                next if key == 'friendfeed_comm' || key == 'friendfeed_like'
                post_data[:metrics][key.to_sym] = value
              end
              @table.reload
            end
          end
        end
      end
    end
  end
end

class DataRequest
  def get(url, &blk)
    @buf = NSMutableData.new
    @blk = blk
    req = NSURLRequest.requestWithURL(NSURL.URLWithString(url))
    NSURLConnection.alloc.initWithRequest(req, delegate:self)
  end
  
  def connection(conn, didReceiveResponse:resp)
    @response = resp
    @buf.setLength(0)
  end
  
  def connection(conn, didReceiveData:data)
    @buf.appendData(data)
  end

  def connection(conn, didFailWithError:err)
    NSLog "Request failed"
  end
  
  def connectionDidFinishLoading(conn)
    @blk.call(NSString.alloc.initWithData @buf, encoding:NSUTF8StringEncoding)
  end
end

class PostRankCell < NSCell
  def drawInteriorWithFrame(frame, inView:view)
    m = objectValue[:color].match(/#(..)(..)(..)/)
    NSColor.colorWithCalibratedRed(m[1].hex/ 255.0, green:m[2].hex/255.0, blue:m[3].hex/255.0, alpha:100).set
    NSRectFill(frame)
  
    rank_frame = NSMakeRect(frame.origin.x + (frame.size.width / 2) - 12,
                           frame.origin.y + (frame.size.height / 2) - 8, frame.size.width, 17)
  
    objectValue[:value].to_s.drawInRect(rank_frame, withAttributes:nil)
  end
end

class PostCell < NSCell
  ROW_HEIGHT = 20
  NUM_METRICS_PER_ROW = 6
  SPRITE_SIZE = 16
  
  @@sprites = {:default => 0, :blogines => 16, :reddit => 32, :reddit_votes => 32,
      :technorati => 48, :magnolia => 64, :digg => 80, :twitter => 96, :comments => 112,
      :icerocket => 128, :delicious => 144, :google => 160, :pownce => 176, :views => 192,
      :bookmarks => 208, :clicks => 224, :jaiku => 240, :digg_comments => 256,
      :diigo => 272, :feecle => 288, :brightkite => 304, :furl => 320, :twitarmy => 336,
      :identica => 352, :ff_likes => 368, :blip => 384, :tumblr => 400,
      :reddit_comments => 416, :ff_comments => 432}
  @@sprite = nil

  def drawInteriorWithFrame(frame, inView:view)
    unless @@sprite
      bundle = NSBundle.mainBundle
      @@sprite = NSImage.alloc.initWithContentsOfFile(bundle.pathForResource("sprites", ofType:"png"))
      @@sprite.setFlipped(true)
    end

  	title_rect = NSMakeRect(frame.origin.x, frame.origin.y + 1, frame.size.width, 17)
  	metrics_rect = NSMakeRect(frame.origin.x, frame.origin.y + ROW_HEIGHT, frame.size.width, 17)

    title_str = "#{objectValue[:title]}"
    title_str.drawInRect(title_rect, withAttributes:nil)

    count = 0
    orig_x_orign = metrics_rect.origin.x
    
    objectValue[:metrics].each_pair do |key, value|
      s = metrics_rect.size.width
      metrics_rect.size.width = SPRITE_SIZE
      
      y = if @@sprites.has_key?(key)
        @@sprites[key.to_sym]
      else
        0
      end
      r = NSMakeRect(0, y, SPRITE_SIZE, SPRITE_SIZE)
      @@sprite.drawInRect(metrics_rect, fromRect:r,
                          operation:NSCompositeSourceOver, fraction:1.0)
      metrics_rect.origin.x += 21
      metrics_rect.size.width = s - 21
      
      value = value.to_i
      "#{value}".drawInRect(metrics_rect, withAttributes:nil)
      s = "#{value}".sizeWithAttributes(nil)
      metrics_rect.origin.x += s.width + 15
      
      count += 1
      if count == NUM_METRICS_PER_ROW
        metrics_rect.origin.y += ROW_HEIGHT
        metrics_rect.origin.x = orig_x_orign
        count = 0
      end
    end
  end
end

Postie.new.start
