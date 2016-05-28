require 'json'
require 'open-uri'
require 'nokogiri'
require 'logger'
require 'csv'

class Array
  def delete_first!(val=nil, &block)
    i = block_given? ? self.index(&block) : self.index(val)
    self.delete_at(i) unless i
    i && self
  end

  def delete_first(val=nil, &block)
    clone_self = self.dup
    clone_self.delete_first!(val, &block)
    clone_self
  end

  def rdelete_first!(val=nil, &block)
    i = block_given? ? self.rindex(&block) : self.rindex(val)
    self.delete_at(i) unless i
    i && self
  end

  def rdelete_first(val=nil, &block)
    clone_self = self.dup
    clone_self.rdelete_first!(val, &block)
    clone_self
  end
end

class Scraping
  def initialize()
    @console = Logger.new(STDOUT)
  end

  def openJSON(filePath)
    @console.debug(filePath)
    json = open(filePath) do |io|
      JSON.load(io)
    end
    return json
  end

  ############################################################
  # Champion                                                 #
  ############################################################

  def scrapingChampion(championName)
    url = "http://leagueoflegends.wikia.com/wiki/Template:Data_" + championName
    @console.debug(url)

    charset = nil
    html = open(url) do |f|
        charset = f.charset
        f.read
    end
    doc = Nokogiri::HTML.parse(html, nil, charset)

    data = Hash.new
    table = doc.at_xpath('//table[@class="wikitable"]')
    table.xpath("tr").each do |tr|
      td = tr.xpath('td')
      unless td.empty? then
        data[td[0].content] = td[1].content
      end
    end
    # @console.debug(data)
    return data
  end

  def compareChampion(name, riot, wikia)
    diffs = Array.new
    key = {
      "role" => "herotype,alttype", "armor" => "arm_base", "armorperlevel" => "arm_lvl",
      "attackdamage" => "dam_base", "attackdamageperlevel" => "dam_lvl", "attackrange" => "range",
      "attackspeedoffset" => "as_base", "attackspeedperlevel" => "as_lvl",
      "hp" => "hp_base", "hpperlevel" => "hp_lvl",
      "hpregen" => "hp5_base", "hpregenperlevel" => "hp5_lvl",
      "movespeed" => "ms",
      "mp" => "mp_base", "mpperlevel" => "mp_lvl",
      "mpregen" => "mp5_base", "mpregenperlevel" => "mp5_lvl",
      "spellblock" => "mr_base", "spellblockperlevel" => "mr_lvl",
      "attack" => "attack", "defense" => "health", "magic" => "spells", "difficulty" => "difficulty",
    }

    riot = riot.merge(riot["stats"])
    riot.delete("stats")
    riot = riot.merge(riot["info"])
    riot.delete("info")
    key.each do |riotK, wikiaK|
      @console.debug("----")
      @console.debug(riotK)
      @console.debug(wikiaK)

      riotV = riot[riotK]

      # アタックスピードは計算必須
      if riotK === "attackspeedoffset" then
        riotV = riotV.to_f
        riotV = 0.625 / (1.0 + riotV)
        riotV = riotV.round(3)
        riotV = sprintf("%.3f", riotV)
      end
      @console.debug(riotV)

      # チャンピオンのロール判定。扱いが異なるので整形している。
      wikiaV = nil
      keys = wikiaK.split(",")
      keys.each do |key|
        value = wikia[key]
        if keys.length > 1 then
          if value != "" then
            wikiaV = wikiaV == nil ? value.to_s : wikiaV.to_s + " / " + value.to_s
          end
        else
          wikiaV = value
        end
      end
      @console.debug(wikiaV)

      if riotK === "attackdamage" || riotK === "hp" || riotK === "mp" || riotK === "attackdamageperlevel" || riotK === "spellblock" || riotK === "armor" then
        # 値のブレ(.0があったりなかったり)を補正
        riotV = riotV.to_f.round(0)
        wikiaV = wikiaV.to_f.round(0)
      elsif riotK === "mpregen" || riotK === "armorperlevel" || riotK === "hpregenperlevel" || riotK === "attackspeedperlevel"
        # 桁数のブレを補正
        riotV = riotV.to_f.round(1)
        wikiaV = wikiaV.to_f.round(1)
      end
      riotV = riotV.to_s
      wikiaV = wikiaV.to_s

      if riotV === wikiaV then
        @console.debug("no diff")
      else
        @console.debug("is diff")
        diff = [name, riotK, riotV, wikiaV]
        diffs.push(diff)
      end
    end
    return diffs
  end

  def champion(version)
    dir = "./riot/champs/" + version
    @console.debug(dir)
    diffs = Array.new
    Dir.glob(dir + "/*").each do |filePath|
      begin
        riot = openJSON(filePath)
        riotEN = riot["EN"]

        page = riotEN["name"].gsub(" ", "_")
        wikia = scrapingChampion(page)

        diff = compareChampion(page, riotEN, wikia)
        if !diff.empty? then
          diffs.push(diff)
        end
      rescue => e
        puts "error, #{e.message}"
        puts e.backtrace.join("\n")
      end
    end

    # TSV変換
    date = Date.today.strftime("%Y%m%d")
    CSV.open("./riot/diff_" + date + "_champion_" + version + ".tsv", "w", { :encoding => "UTF-8", :col_sep => "\t", :quote_char => '"', :force_quotes => true }) do |tsv|
      tsv << ["Name", "Key", "Riot", "Wikia"]
      diffs.each do |diff|
        diff.each do |row|
          tsv << row
        end
      end
    end
  end

  ############################################################
  # Item                                                     #
  ############################################################

  def scrapingItem(itemName)
    console = Logger.new(STDOUT)
    url = "http://leagueoflegends.wikia.com/wiki/Template:Item_data_" + itemName

    charset = nil
    html = open(url) do |f|
        charset = f.charset
        f.read
    end
    doc = Nokogiri::HTML.parse(html, nil, charset)

    data = Hash.new
    table = doc.at_xpath('//table[@class="article-table grid"]')
    table.xpath("tr").each do |tr|
      td = tr.xpath('td')
      unless td.empty? then
        key = td[0].content
        key = key.to_s.gsub(/(\s)/, '').gsub('\n', '')
        value = td[1].content
        value = value.to_s.gsub(/(\s)/, '').gsub('\n', '')
        data[key] = value
      end
    end
    return data
  end

  def compareItem(name, riot, wikia)
    diffs = Array.new
    key = {
      "total" => "buy", "base" => "comb", "sell" => "sell", "from" => "recipe",
    }
    key.each do |riotK, wikiaK|
      @console.debug("----")
      @console.debug(riotK)
      @console.debug(wikiaK)

      riotV = riot[riotK].to_s
      wikiaV = wikia[wikiaK].to_s
      @console.debug(riotV == "0" ? "" : riotV)
      @console.debug(wikiaV)

      if riotK == "from" then
        fromNames = Array.new
        recipeNames = Array.new

        froms = riot["from"]
        recipes = wikia["recipe"].split(",")

        # 素材アイテムの判定
        ### Ruby初心者すぎて複雑。。。
        removeNames = Array.new
        recipes.each do |recipe|
          recipeName = recipe.gsub(" ", "").gsub("'", "").gsub("-", "_").gsub(".", "")
          recipeNames.push(recipeName)

          froms.each do |from|
            # CrystalScarの扱いブレ補正
            fromName = from["name"].gsub("CrystalScar", "(CrystalScar)")
            fromNames.push(fromName)

            if recipeName == fromName then
              @console.debug("no diff is remove " + recipeName + " / " + fromName)
              index = froms.index { |f| f == from }
              froms.delete(index)
              removeNames.push(recipe)
              break
            end
          end
        end
        recipes = recipes.delete_if { |r| removeNames.include?(r) }

        # 異なる素材が存在すれば差分ありと判定
        fLength = froms == nil ? 0 : froms.length
        rLength = recipes == nil ? 0 : recipes.length
        if fLength == 0 || rLength == 0 then
          @console.debug("no diff")
        else
          @console.debug("is diff")
          fromNameOut = fromNames.uniq!.join(",")
          recipeNameOut = recipeNames.join(",")
          diff = [name, riotK, fromNameOut, recipeNameOut]
          diffs.push(diff)
        end
      else
        # ベース価格の差異があるため補正
        wikiaV = wikiaV.empty? ? 0 : wikiaV
        if riotK == "base" && wikiaV == 0 then
          wikiaV = wikia["buy"].to_s
          wikiaV = wikiaV.empty? ? 0 : wikiaV
        end
        wikiaV = wikiaV.to_s

        if riotV == wikiaV then
          @console.debug("no diff")
        else
          @console.debug("is diff")
          diff = [name, riotK, riotV, wikiaV]
          diffs.push(diff)
        end
      end
    end
    return diffs
  end

  def item(version)
    dir = "./riot/items/" + version
    @console.debug(dir)
    diffs = Array.new
    Dir.glob(dir + "/*").each do |filePath|
      begin
        riot = openJSON(filePath)
        riotEN = riot["EN"]

        page = riotEN["name"].gsub(" ", "_")
        wikia = scrapingItem(page)

        diff = compareItem(page, riotEN, wikia)
        if !diff.empty? then
          diffs.push(diff)
        end
      rescue => e
        puts "error, #{e.message}"
        puts e.backtrace.join("\n")
      end
    end

    # TSV変換
    date = Date.today.strftime("%Y%m%d")
    CSV.open("./riot/diff_" + date + "_item_" + version + ".tsv", "w", { :encoding => "UTF-8", :col_sep => "\t", :quote_char => '"', :force_quotes => true }) do |tsv|
      tsv << ["Name", "Key", "Riot", "Wikia"]
      diffs.each do |diff|
        diff.each do |row|
          tsv << row
        end
      end
    end
  end

  ############################################################
  # Main                                                     #
  ############################################################

  def main
    filePath = "./riot/versions.json"
    versions = openJSON(filePath)

    # champion(versions[0])
    item(versions[0])
  end
end

run = Scraping.new
run.main
