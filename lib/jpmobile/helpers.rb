# =携帯向けにUrlHelperをカスタマイズ
module ActionView::Helpers::UrlHelper
  alias_method :url_for_original, :url_for
  # docomo からのアクセスの場合、必ずクエリに guid=ON をつけて URL を構築する
  def url_for(options = {})
    if request && request.mobile? && (request.mobile.kind_of? Jpmobile::Mobile::Docomo)
      is_docomo = true
    end
    case options
    when Hash
      options[:guid] = "ON" if is_docomo
      show_path =  options[:host].nil? ? true : false
      options = { :only_path => show_path }.update(options.symbolize_keys)
      escape  = options.key?(:escape) ? options.delete(:escape) : true
      url     = @controller.send(:url_for, options)
    when String
      escape = true
      url    = options
      url    = url + (options.index('?') ? "&" : "?") + "guid=ON" if is_docomo
    when NilClass
      opt = is_docomo ? {:guid=>"ON"} : nil
      url = @controller.send(:url_for, opt)
    else
      escape = false
      url    = polymorphic_path(options)
    end
    
    escape ? escape_once(url) : url
  end

  # インラインでリンク色を変えたいときの link_to 拡張
  # a style だとドコモとauで色反映されないので、span style で流し込む
  def link_to_with_style(name, options = {}, html_options = {})
    if style = html_options.delete(:style) then
      name = "<span style='#{style}'>#{name}</span>"
    end
    link_to_without_style(name, options, html_options)
  end
  alias_method_chain :link_to, :style
end

# =docomo 用にUrl(Re)?Writer を拡張。必ず "guid=ON" をクエリにつけるようにする
module ActionController 
  module UrlWriter
    alias_method :url_for_original, :url_for
    def url_for(options)
      options[:guid] = "ON"
      url_for_original(options)
    end
  end
  class UrlRewriter
    alias_method :rewrite_original, :rewrite
    def rewrite(options = {})
      if @request && @request.mobile? && (@request.mobile.kind_of? Jpmobile::Mobile::Docomo)
        is_docomo = true
      end
      if is_docomo
        options[:guid] = "ON"
      end
      rewrite_original(options)
    end
  end
end

# =位置情報等を要求するヘルパー
module Jpmobile
  # 携帯電話端末に位置情報を要求するための、特殊なリンクを出力するヘルパー群。
  # 多くのキャリアでは特殊なFORMでも位置情報を要求できる。
  module Helpers
    # 位置情報(緯度経度がとれるもの。オープンiエリアをのぞく)要求するリンクを作成する。
    # 位置情報を受け取るページを +url_for+ に渡す引数の形式で +options+ に指定する。
    # :show_all => +true+ とするとキャリア判別を行わず全てキャリアのリンクを返す。
    # 第1引数に文字列を与えるとその文字列をアンカーテキストにする。
    # 第1引数がHashの場合はデフォルトのアンカーテキストを出力する。
    def get_position_link_to(str=nil, options={})
      if str.is_a?(Hash)
        options = str
        str = nil
      end
      show_all = nil
      if options.is_a?(Hash)
        options = options.symbolize_keys
        show_all = options.delete(:show_all)
      end

      # TODO: コード汚い
      s = []
      if show_all || request.mobile.instance_of?(Mobile::Docomo)
        s << docomo_foma_gps_link_to(str||"DoCoMo FOMA(GPS)", options)
      end
      if show_all || request.mobile.instance_of?(Mobile::Au)
        if show_all || request.mobile.supports_gps?
          s << au_gps_link_to(str||"au(GPS)", options)
        end
        if show_all || (!(request.mobile.supports_gps?) && request.mobile.supports_location?)
          s << au_location_link_to(str||"au(antenna)", options)
        end
      end
      if show_all || request.mobile.instance_of?(Mobile::Jphone)
        s << jphone_location_link_to(str||"Softbank(antenna)", options)
      end
      if show_all || request.mobile.instance_of?(Mobile::Vodafone) || request.mobile.instance_of?(Mobile::Softbank)
        s << softbank_location_link_to(str||"Softbank 3G(GPS)", options)
      end
      if show_all || request.mobile.instance_of?(Mobile::Willcom)
        s << willcom_location_link_to(str||"Willcom", options)
      end
      return s.join("<br>\n")
    end

    # DoCoMo FOMAでGPS位置情報を取得するためのリンクを返す。
    def docomo_foma_gps_link_to(str, options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        url = url_for(options)
      end
      return %{<a href="#{url}" lcs>#{str}</a>}
    end

    # DoCoMoでオープンiエリアを取得するためのURLを返す。
    def docomo_openiarea_url_for(options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        posinfo = options.delete(:posinfo) || "1" # 基地局情報を元に測位した緯度経度情報を要求
        url = url_for(options)
      end
      return "http://w1m.docomo.ne.jp/cp/iarea?ecode=OPENAREACODE&msn=OPENAREAKEY&posinfo=#{posinfo}&nl=#{CGI.escape(url)}"
    end

    # DoCoMoでオープンiエリアを取得するためのリンクを返す。
    def docomo_openiarea_link_to(str, options={})
      link_to_url(str, docomo_openiarea_url_for(options))
    end

    # DoCoMoで端末製造番号等を取得するためのリンクを返す。
    def docomo_utn_link_to(str, options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        url = url_for(options)
      end
      return %{<a href="#{url}" utn>#{str}</a>}
    end

    # DoCoMoでiモードIDを取得するためのリンクを返す。
    def docomo_guid_link_to(str, options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:guid] = "ON"
        url = url_for(options)
      end
      return link_to_url(str, url)
    end

    # au GPS位置情報を取得するためのURLを返す。
    def au_gps_url_for(options={})
      url = options
      datum = 0 # 0:wgs84, 1:tokyo
      unit = 0 # 0:dms, 1:deg
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        datum = (options.delete(:datum) || 0 ).to_i # 0:wgs84, 1:tokyo
        unit = (options.delete(:unit) || 0 ).to_i # 0:dms, 1:deg
        url = url_for(options)
      end
      return "device:gpsone?url=#{CGI.escape(url)}&ver=1&datum=#{datum}&unit=#{unit}&acry=0&number=0"
    end

    # au GPS位置情報を取得するためのリンクを返す。
    def au_gps_link_to(str, options={})
      link_to_url(str, au_gps_url_for(options))
    end

    # au 簡易位置情報を取得するためのURLを返す。
    def au_location_url_for(options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        url = url_for(options)
      end
      return "device:location?url=#{CGI.escape(url)}"
    end

    # au 簡易位置情報を取得するためのリンクを返す。
    def au_location_link_to(str, options={})
      link_to_url(str, au_location_url_for(options))
    end

    # J-PHONE 位置情報 (基地局) を取得するためのリンクを返す。
    def jphone_location_link_to(str,options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        url = url_for(options)
      end
      return %{<a z href="#{url}">#{str}</a>}
    end

    # Softbank(含むVodafone 3G)で位置情報を取得するためのURLを返す。
    def softbank_location_url_for(options={})
      url = options
      mode = "auto"
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        mode = options[:mode] || "auto"
        url = url_for(options)
      end
      return "location:#{mode}?url=#{url}"
    end

    # Softbank(含むVodafone 3G)で位置情報を取得するためのリンクを返す。
    def softbank_location_link_to(str,options={})
      link_to_url(str,softbank_location_url_for(options))
    end

    # Willcom 基地局位置情報を取得するためのURLを返す。
    def willcom_location_url_for(options={})
      url = options
      if options.is_a?(Hash)
        options = options.symbolize_keys
        options[:only_path] = false
        url = url_for(options)
      end
      return "http://location.request/dummy.cgi?my=#{url}&pos=$location"
    end

    # Willcom 基地局位置情報を取得するためのリンクを返す。
    def willcom_location_link_to(str,options={})
      link_to_url(str, willcom_location_url_for(options))
    end

    # 各キャリア向けXHTMLのDOCTYPE宣言を返す。
    def carrier_doctype
      case request.mobile
      when Jpmobile::Mobile::Docomo
        # for DoCoMo
        '<!DOCTYPE html PUBLIC "-//i-mode group (ja)//DTD XHTML i-XHTML(Locale/Ver.=ja/1.1) 1.0//EN" "i-xhtml_4ja_10.dtd">'
      when Jpmobile::Mobile::Au
        # for au
        '<!DOCTYPE html PUBLIC "-//OPENWAVE//DTD XHTML 1.0//EN" "http://www.openwave.com/DTD/xhtml-basic.dtd">'
      when Jpmobile::Mobile::Softbank
        # for SoftBank
        '<!DOCTYPE html PUBLIC "-//JPHONE//DTD XHTML Basic 1.0 Plus//EN" "xhtml-basic10-plus.dtd">'
      end
    end

    # 各キャリア向けXHTML用のmeta要素を返す。
    def carrier_meta_tag
      case request.mobile
      when Jpmobile::Mobile::Docomo
        # for DoCoMo
        '<meta http-equiv="Content-Type" content="application/xhtml+xml; charset=Shift_JIS" />'
      when Jpmobile::Mobile::Au
        # for au
        '<meta http-equiv="content-type" content="text/html;charset=Shift_JIS" />'+ "\n" + 
        '<meta http-equiv="Cache-Control" content="no-cache" />'
      when Jpmobile::Mobile::Softbank
        # for SoftBank
        '<meta http-equiv="content-type" content="text/html;charset=Shift_JIS" />'
      end
    end

    # キャリアごとに適当にエンコードされた mailto 文字列を構築するヘルパ。
    def mobile_mailto(to = nil, subject = nil, body = nil)
      buff = "mailto:"
      buff += to if to
      queries = []
      if subject
        case request.mobile
        when Jpmobile::Mobile::Docomo, Jpmobile::Mobile::Au
          # for DoCoMo or au: Shift_JIS にして urlencode
          queries << "subject=" + CGI.escape(NKF.nkf('-Ws -m0 --cp932', subject))
        when Jpmobile::Mobile::Softbank
          # for SoftBank: UTF8 のまま urlencode
          queries << "subject=" + CGI.escape(subject)
        end
      end
      if body
        case request.mobile
        when Jpmobile::Mobile::Docomo, Jpmobile::Mobile::Au
          # for DoCoMo or au: Shift_JIS にして urlencode
          queries << "body=" + CGI.escape(NKF.nkf('-Ws -m0 --cp932', body))
        when Jpmobile::Mobile::Softbank
          # for SoftBank: UTF8 のまま urlencode
          queries << "body=" + CGI.escape(body)
        end
      end
      unless queries.empty?
        buff += "?" + queries.join("&amp;")
      end
      buff
    end
    alias :mailto :mobile_mailto

    # input type="text" でデフォルト文字種別や長さを指定してタグを構築する。
    # mode に :alphabet, :number, :hiragana(デフォルト) を指定する。
    def inputtext_tag(attributes)
      buff = ""
      case request.mobile
      when Jpmobile::Mobile::Docomo
        if attributes[:mode] == :alphabet then
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" maxlength="#{attributes[:maxlength]}" size="#{attributes[:size]}" style="-wap-input-format:'*&lt;ja:en&gt;';" />
EOT
        elsif attributes[:mode] == :number then
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" maxlength="#{attributes[:maxlength]}" size="#{attributes[:size]}" style="-wap-input-format:'*&lt;ja:n&gt;';" />
EOT
        else
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" maxlength="#{attributes[:maxlength]*2}" size="#{attributes[:size]}" style="-wap-input-format:'*&lt;ja:h&gt;';" />
EOT
        end
      when Jpmobile::Mobile::Au
        if attributes[:mode] == :alphabet then
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" size="#{attributes[:size]}" format="#{attributes[:maxlength]}x" />
EOT
        elsif attributes[:mode] == :number then
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" size="#{attributes[:size]}" format="#{attributes[:maxlength]}N" />
EOT
        else
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" size="#{attributes[:size]}" format="#{attributes[:maxlength]}M" />
EOT
        end
      when Jpmobile::Mobile::Softbank
        if attributes[:mode] == :alphabet then
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" size="#{attributes[:size]}" format="#{attributes[:maxlength]}x" mode="alphabet" maxlength="#{attributes[:maxlength]}" />
EOT
        elsif attributes[:mode] == :number then
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" size="#{attributes[:size]}" format="#{attributes[:maxlength]}N" mode="numeric" maxlength="#{attributes[:maxlength]}" />
EOT
        else
          buff = <<EOT
<input type="text" name="#{attributes[:name]}" value="#{attributes[:value]}" size="#{attributes[:size]}" format="#{attributes[:maxlength]}M" mode="hiragana" maxlength="#{attributes[:maxlength]}" />
EOT
        end
      end
      buff
    end

    # URLパラメタに日本語を含める場合の文字コード変換処理。
    # SoftBank のみ Unicode を送出するので変換してやる必要なし。
    def to_query(q)
      case request.mobile
      when Jpmobile::Mobile::Docomo, Jpmobile::Mobile::Au
        CGI.escape(NKF.nkf('-Ws -m0 --cp932', q))
      else
        CGI.escape(q)
      end
    end

    private
    # 外部へのリンク
    def link_to_url(str, url)
      %{<a href="#{url}">#{str}</a>}
    end

  end
end
