#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# RubyKaigi2025 タイムテーブル取得・解析プログラム

require 'nokogiri'
require 'open-uri'
require 'date'
require 'json'
require 'optparse'

class RubyKaigiScheduleParser
  SCHEDULE_URL = 'https://rubykaigi.org/2025/schedule/'
  
  def initialize(url = nil)
    @url = url || SCHEDULE_URL
    begin
      puts "ウェブサイトからスケジュール情報を取得しています..."
      @doc = Nokogiri::HTML(URI.open(@url))
      puts "スケジュール情報の取得に成功しました。"
    rescue => e
      puts "エラー: スケジュール情報の取得に失敗しました。"
      puts e.message
      exit 1
    end
    
    @schedule = {
      'day1' => { date: 'Apr 16', events: [] },
      'day2' => { date: 'Apr 17', events: [] },
      'day3' => { date: 'Apr 18', events: [] }
    }
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
          
          # リンク情報を取得
          link = schedule_item.parent['href'] if schedule_item.parent.name == 'a'

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
          markdown += "- **#{event[:time_slot]}** #{event[:title]}#{meta_info} - #{speaker_names}#{venue_info}\n"
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
          markdown += "- **#{event[:time_slot]}** #{event[:title]}#{meta_info} - #{speaker_names}#{venue_info}\n"
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
          venue_info = keynote[:venue] ? " at #{keynote[:venue]}" : ""
          markdown += "- **#{keynote[:time_slot]}** #{keynote[:title]} - #{speaker_names}#{venue_info}\n"
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

  opts.on("-h", "--help", "ヘルプを表示") do
    puts opts
    exit
  end
end

option_parser.parse!

# メイン処理
parser = RubyKaigiScheduleParser.new(options[:url])
parser.parse

# デフォルトではサマリーを表示
parser.print_summary

# ファイル保存オプションの処理
parser.save_markdown(options[:markdown]) if options[:markdown]
parser.save_json(options[:json]) if options[:json]