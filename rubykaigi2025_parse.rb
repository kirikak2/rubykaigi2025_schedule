#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# RubyKaigi2025 タイムテーブル取得・解析プログラム

require 'nokogiri'
require 'open-uri'
require 'date'
require 'json'
require 'optparse'
require 'uri'

class RubyKaigiScheduleParser
  SCHEDULE_URL = 'https://rubykaigi.org/2025/schedule/'
  BASE_URL = 'https://rubykaigi.org'
  
  attr_reader :schedule
  
  def initialize(url = nil, fetch_details = false)
    @url = url || SCHEDULE_URL
    @fetch_details = fetch_details
    @schedule = {
      'day1' => { date: 'Apr 16', events: [] },
      'day2' => { date: 'Apr 17', events: [] },
      'day3' => { date: 'Apr 18', events: [] }
    }
    
    begin
      puts "ウェブサイトからスケジュール情報を取得しています..."
      @doc = Nokogiri::HTML(URI.open(@url))
      puts "スケジュール情報の取得に成功しました。"
    rescue => e
      puts "エラー: スケジュール情報の取得に失敗しました。"
      puts e.message
      exit 1
    end
  end

  def parse
    # 各日付の正確な表示を取得
    @doc.css('.m-day-tabs__item').each do |item|
      day_id = item['data-day']
      date = item.text.strip
      @schedule[day_id][:date] = date if @schedule[day_id]
    end

    # 各日のタブパネルを取得して処理
    @schedule.each_key do |day_id|
      day_pane = @doc.css(".tab-pane[data-day='#{day_id}']").first
      next unless day_pane
      
      parse_day(day_id, day_pane)
    end
    
    # 詳細情報を取得するかどうか
    if @fetch_details
      fetch_session_details
    end

    @schedule
  end
  
  def parse_day(day_id, day_pane)
    # ベニュー情報を取得
    venues = []
    day_pane.css('th.m-schedule-table__room:not(.is-blank)').each do |room|
      room_name = room.css('.m-schedule-table__room-name').text.strip
      room_tag = room.css('.m-schedule-table__room-tag').text.strip
      venues << { name: room_name, tag: room_tag } if room_name
    end
    @schedule[day_id][:venues] = venues
    
    # すべての行を処理
    day_pane.css('tr').each do |row|
      time_cell = row.css('.m-schedule-table__time').first
      next unless time_cell

      # 時間情報を取得
      time_elements = time_cell.css('time')
      next if time_elements.empty?
      
      start_time = time_elements.first.text.strip
      end_time = time_elements.last.text.strip
      time_slot = "#{start_time}-#{end_time}"

      # 休憩時間かチェック
      if row['class'] && row['class'].include?('m-schedule-table__break')
        break_text = row.css('.m-schedule-table__event.is-break span').text.strip
        @schedule[day_id][:events] << {
          time_slot: time_slot,
          type: 'break',
          title: break_text
        }
      else
        # 各部屋のセッションを取得
        row.css('.m-schedule-table__event').each_with_index do |cell, index|
          schedule_item = cell.css('.m-schedule-item').first
          next unless schedule_item

          title_elem = schedule_item.css('.m-schedule-item__title').first
          next unless title_elem
          
          title = title_elem.text.strip
          
          # スピーカー情報
          speakers = []
          schedule_item.css('.m-schedule-item-speaker').each do |speaker|
            name = speaker.css('.m-schedule-item-speaker__name').text.strip
            id = speaker.css('.m-schedule-item-speaker__id').text.strip
            speakers << { name: name, id: id } if name
          end

          # メタ情報（言語、セッションタイプなど）
          meta = []
          schedule_item.css('.m-schedule-item__meta span').each do |meta_span|
            meta << meta_span.text.strip
          end
          
          # リンク情報を取得（スケジュールページから）
          link_element = schedule_item.at_css('a')
          link = link_element ? link_element['href'] : nil
          
          # 会場情報
          venue = index < venues.length ? venues[index][:name] : 'Unknown Venue'

          @schedule[day_id][:events] << {
            time_slot: time_slot,
            type: 'session',
            title: title,
            speakers: speakers,
            meta: meta,
            venue: venue,
            link: link
          }
        end
      end
    end
  end
  
  def fetch_session_details
    puts "各セッションの詳細情報を取得しています..."
    total_sessions = 0
    processed = 0
    
    @schedule.each do |day_id, day_data|
      day_data[:events].each do |event|
        next unless event[:type] == 'session' && event[:link]
        total_sessions += 1
      end
    end
    
    @schedule.each do |day_id, day_data|
      day_data[:events].each do |event|
        next unless event[:type] == 'session' && event[:link]
        
        processed += 1
        puts "セッション詳細を取得中 (#{processed}/#{total_sessions}): #{event[:title]}"
        
        begin
          # 詳細ページのURLを作成
          # URLのパターンは: https://rubykaigi.org/2025/presentations/[speaker_id].html#[day_id]
          if event[:speakers].empty?
            puts "  警告: #{event[:title]} にはスピーカー情報がありません。詳細情報をスキップします。"
            next
          end
          
          speaker_id = event[:speakers].first[:id]&.delete('@')
          detail_url = "#{BASE_URL}/2025/presentations/#{speaker_id}.html##{day_id}"
          puts "  アクセスするURL: #{detail_url}"
          
          detail_doc = Nokogiri::HTML(URI.open(detail_url))
          
          # 概要を取得
          description = detail_doc.css('.m-presentation-content__description .e-long-text').text.strip
          event[:description] = description if description && !description.empty?
          
          # スピーカーの詳細情報を取得
          detail_doc.css('.m-member.is-speaker').each_with_index do |speaker_elem, idx|
            next if idx >= event[:speakers].length
            
            # スピーカーのプロフィール情報
            bio = speaker_elem.css('.m-member__description').text.strip
            event[:speakers][idx][:bio] = bio if bio && !bio.empty?
            
            # SNSリンクを取得
            sns_links = {}
            speaker_elem.css('.m-member__sns-item.is-icon a').each do |link|
              if link['class'].include?('is-github')
                sns_links[:github] = link['href']
              elsif link['class'].include?('is-twitter')
                sns_links[:twitter] = link['href']
              end
            end
            
            event[:speakers][idx][:sns] = sns_links unless sns_links.empty?
          end
          
          # スリープを入れて過剰なリクエストを防止
          sleep(1)
        rescue => e
          puts "  警告: #{event[:title]} の詳細情報取得に失敗: #{e.message}"
        end
      end
    end
    
    puts "セッション詳細の取得が完了しました。"
  end

  def print_summary
    puts "# RubyKaigi2025 タイムテーブルサマリー"
    @schedule.each do |day_id, day_data|
      puts "\n## #{day_id.upcase}: #{day_data[:date]}"

      # イベントを時間順にソート
      sorted_events = day_data[:events].sort_by { |e| e[:time_slot].split('-').first }

      # 午前と午後のセッションを分ける
      morning_events = []
      afternoon_events = []

      sorted_events.each do |event|
        start_hour = event[:time_slot].split('-').first.to_i
        if start_hour < 12
          morning_events << event
        else
          afternoon_events << event
        end
      end

      puts "\n### 午前"
      last_time_slot = ""
      morning_events.each do |event|
        time_display = event[:time_slot] != last_time_slot ? event[:time_slot] : " " * 11
        last_time_slot = event[:time_slot]

        if event[:type] == 'break'
          puts "#{time_display} | #{event[:title]}"
        else
          speaker_names = event[:speakers].map { |s| s[:name] }.join(', ')
          meta_info = event[:meta].any? ? " (#{event[:meta].join(', ')})" : ""
          puts "#{time_display} | #{event[:title]}#{meta_info} - #{speaker_names}"
          
          # 概要があれば出力
          if event[:description]
            puts "#{' ' * 11} | 概要: #{event[:description].gsub(/\s+/, ' ').strip}"
          end
        end
      end

      puts "\n### 午後"
      last_time_slot = ""
      afternoon_events.each do |event|
        time_display = event[:time_slot] != last_time_slot ? event[:time_slot] : " " * 11
        last_time_slot = event[:time_slot]

        if event[:type] == 'break'
          puts "#{time_display} | #{event[:title]}"
        else
          speaker_names = event[:speakers].map { |s| s[:name] }.join(', ')
          meta_info = event[:meta].any? ? " (#{event[:meta].join(', ')})" : ""
          puts "#{time_display} | #{event[:title]}#{meta_info} - #{speaker_names}"
          
          # 概要があれば出力
          if event[:description]
            puts "#{' ' * 11} | 概要: #{event[:description].gsub(/\s+/, ' ').strip}"
          end
        end
      end
    end

    # キーノートセッションを特別に強調
    puts "\n## 主要セッション"
    @schedule.each do |day_id, day_data|
      keynotes = day_data[:events].select do |e|
        e[:type] == 'session' && e[:meta].any? { |m| m.include?('Keynote') }
      end

      if keynotes.any?
        puts "\n### #{day_id.upcase} キーノート:"
        keynotes.each do |keynote|
          speaker_names = keynote[:speakers].map { |s| s[:name] }.join(', ')
          puts "- #{keynote[:time_slot]}: #{keynote[:title]} - #{speaker_names}"
          if keynote[:description]
            puts "  概要: #{keynote[:description].gsub(/\s+/, ' ').strip}"
          end
        end
      end
    end
  end

  def generate_markdown
    markdown = "# RubyKaigi2025 タイムテーブルサマリー\n\n"

    @schedule.each do |day_id, day_data|
      date_display = day_data[:date]
      markdown += "## #{day_id.upcase}: #{date_display}\n\n"

      # 午前と午後のセッションを分ける
      morning_events = []
      afternoon_events = []

      day_data[:events].sort_by { |e| e[:time_slot].split('-').first }.each do |event|
        start_hour = event[:time_slot].split('-').first.to_i
        if start_hour < 12
          morning_events << event
        else
          afternoon_events << event
        end
      end

      markdown += "### 午前\n"
      morning_events.each do |event|
        if event[:type] == 'break'
          markdown += "- **#{event[:time_slot]}** #{event[:title]}\n"
        else
          speaker_names = event[:speakers].map { |s| s[:name] }.join(', ')
          meta_info = event[:meta].any? ? " (#{event[:meta].join(', ')})" : ""
          venue_info = event[:venue] ? " at #{event[:venue]}" : ""
          
          if event[:link]
            markdown += "- **#{event[:time_slot]}** [#{event[:title]}](#{event[:link]})#{meta_info} - #{speaker_names}#{venue_info}\n"
          else
            markdown += "- **#{event[:time_slot]}** #{event[:title]}#{meta_info} - #{speaker_names}#{venue_info}\n"
          end
          
          # 概要があれば出力
          if event[:description]
            markdown += "  - 概要: #{event[:description].gsub(/\s+/, ' ').strip}\n"
          end
          
          # スピーカー情報
          event[:speakers].each do |speaker|
            if speaker[:bio] || (speaker[:sns] && speaker[:sns].any?)
              markdown += "  - **#{speaker[:name]}** (#{speaker[:id]})"
              
              if speaker[:sns]
                sns_links = []
                sns_links << "[GitHub](#{speaker[:sns][:github]})" if speaker[:sns][:github]
                sns_links << "[Twitter](#{speaker[:sns][:twitter]})" if speaker[:sns][:twitter]
                markdown += " - #{sns_links.join(', ')}" if sns_links.any?
              end
              
              markdown += "\n"
              
              if speaker[:bio]
                markdown += "    - #{speaker[:bio].gsub(/\s+/, ' ').strip}\n"
              end
            end
          end
        end
      end

      markdown += "\n### 午後\n"
      afternoon_events.each do |event|
        if event[:type] == 'break'
          markdown += "- **#{event[:time_slot]}** #{event[:title]}\n"
        else
          speaker_names = event[:speakers].map { |s| s[:name] }.join(', ')
          meta_info = event[:meta].any? ? " (#{event[:meta].join(', ')})" : ""
          venue_info = event[:venue] ? " at #{event[:venue]}" : ""
          
          if event[:link]
            markdown += "- **#{event[:time_slot]}** [#{event[:title]}](#{event[:link]})#{meta_info} - #{speaker_names}#{venue_info}\n"
          else
            markdown += "- **#{event[:time_slot]}** #{event[:title]}#{meta_info} - #{speaker_names}#{venue_info}\n"
          end
          
          # 概要があれば出力
          if event[:description]
            markdown += "  - 概要: #{event[:description].gsub(/\s+/, ' ').strip}\n"
          end
          
          # スピーカー情報
          event[:speakers].each do |speaker|
            if speaker[:bio] || (speaker[:sns] && speaker[:sns].any?)
              markdown += "  - **#{speaker[:name]}** (#{speaker[:id]})"
              
              if speaker[:sns]
                sns_links = []
                sns_links << "[GitHub](#{speaker[:sns][:github]})" if speaker[:sns][:github]
                sns_links << "[Twitter](#{speaker[:sns][:twitter]})" if speaker[:sns][:twitter]
                markdown += " - #{sns_links.join(', ')}" if sns_links.any?
              end
              
              markdown += "\n"
              
              if speaker[:bio]
                markdown += "    - #{speaker[:bio].gsub(/\s+/, ' ').strip}\n"
              end
            end
          end
        end
      end

      markdown += "\n"
    end

    # キーノートセッションを特別に強調
    markdown += "## 注目セッション\n\n"
    @schedule.each do |day_id, day_data|
      keynotes = day_data[:events].select do |e|
        e[:type] == 'session' && e[:meta].any? { |m| m.include?('Keynote') }
      end

      if keynotes.any?
        markdown += "### #{day_id.upcase} キーノート\n"
        keynotes.each do |keynote|
          speaker_names = keynote[:speakers].map { |s| s[:name] }.join(', ')
          
          if keynote[:link]
            markdown += "- **#{keynote[:time_slot]}** [#{keynote[:title]}](#{keynote[:link]}) - #{speaker_names}\n"
          else
            markdown += "- **#{keynote[:time_slot]}** #{keynote[:title]} - #{speaker_names}\n"
          end
          
          if keynote[:description]
            markdown += "  - 概要: #{keynote[:description].gsub(/\s+/, ' ').strip}\n"
          end
          
          # スピーカー情報
          keynote[:speakers].each do |speaker|
            markdown += "  - **#{speaker[:name]}** (#{speaker[:id]})"
            
            if speaker[:sns]
              sns_links = []
              sns_links << "[GitHub](#{speaker[:sns][:github]})" if speaker[:sns][:github]
              sns_links << "[Twitter](#{speaker[:sns][:twitter]})" if speaker[:sns][:twitter]
              markdown += " - #{sns_links.join(', ')}" if sns_links.any?
            end
            
            markdown += "\n"
            
            if speaker[:bio]
              markdown += "    - #{speaker[:bio].gsub(/\s+/, ' ').strip}\n"
            end
          end
        end
        markdown += "\n"
      end
    end

    markdown
  end

  def save_markdown(filename)
    File.write(filename, generate_markdown)
    puts "Markdownファイルを#{filename}に保存しました。"
  end

  def save_json(filename)
    File.write(filename, JSON.pretty_generate(@schedule))
    puts "JSONファイルを#{filename}に保存しました。"
  end
end

# コマンドラインオプションの処理
options = {}
option_parser = OptionParser.new do |opts|
  opts.banner = "使用方法: ruby rubykaigi2025_parser.rb [オプション]"

  opts.on("--markdown FILENAME", "Markdownファイルに保存") do |filename|
    options[:markdown] = filename
  end

  opts.on("--json FILENAME", "JSONファイルに保存") do |filename|
    options[:json] = filename
  end
  
  opts.on("--url URL", "スケジュールページのURLを指定 (デフォルト: #{RubyKaigiScheduleParser::SCHEDULE_URL})") do |url|
    options[:url] = url
  end
  
  opts.on("--fetch-details", "各セッションの詳細ページから追加情報を取得する") do
    options[:fetch_details] = true
  end

  opts.on("-h", "--help", "ヘルプを表示") do
    puts opts
    exit
  end
end

option_parser.parse!

# メイン処理
parser = RubyKaigiScheduleParser.new(options[:url], options[:fetch_details])
parser.parse

# デフォルトではサマリーを表示
parser.print_summary

# ファイル保存オプションの処理
parser.save_markdown(options[:markdown]) if options[:markdown]
parser.save_json(options[:json]) if options[:json]