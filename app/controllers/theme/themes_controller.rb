#encoding: utf-8
class Theme::ThemesController < Theme::AppController
  include Admin::ShopsHelper
  prepend_before_filter :authenticate_shop!, only: [:apply, :logout]
  layout 'theme', only: [:index, :show, :download, :apply]

  expose(:permanent_domain) { session[:shop] }
  expose(:shop_url) do
    if session[:shop_url]
      url_with_protocol(session[:shop_url])
    end
  end
  expose(:shop_host) { URI.parse(shop_url).host }
  expose(:handle) { session[:handle] || params[:handle] }
  expose(:style_handle) { session[:style_handle] || params[:style_handle] }
  expose(:theme) { Theme.where(handle: params[:handle], style_handle: params[:style_handle]).first }

  begin 'store'

    def index
      if params[:shop_url] # 从商店后台管理中进入，则之后的操作不需要再提示商店url
        session[:shop_url] = params[:shop_url]
        session[:shop] = nil # 登录名(商店子域名)
        redirect_to theme_store_url_with_port
      end
    end

    def show
      session[:handle] = params[:handle]
      session[:style_handle] = params[:style_handle]
      @theme_json = theme.attributes.to_json
      styles = Theme.where(handle: params[:handle])
      others = Theme.where(author: theme.author).take(4)
      @styles_json = styles.inject([]) do |result, theme|
        result << theme.attributes; result
      end.to_json
      @others_json = others.inject([]) do |result, theme|
        result << { theme: theme.attributes }; result
      end.to_json
    end

    def download # 确认切换主题
      if request.xhr? # ajax
        if permanent_domain
          render text: 'logged'
        elsif shop_url # 从后台管理而来
          render text: 'from_admin'
        else
          redirect_to theme_login_path
        end
      else # html
        redirect_to theme_path(handle: handle, style_handle: style_handle) unless permanent_domain
      end
    end

    def get_shop # 获取商店信息
      access_token = OAuth2::AccessToken.from_hash(client, access_token: token)
      oauth2_response = access_token.get('/api/shop')
      result = JSON(oauth2_response.body)
      if result['error'].blank?
        session[:shop] = result['shop']['name']
      end
      redirect_to theme_download_path(handle: handle, style_handle: style_handle)
    end

    def apply # 切换主题
      if request.post?
        access_token = OAuth2::AccessToken.from_hash(client, access_token: token)
        oauth2_response = access_token.post('/api/themes/install', params: { handle: handle, style_handle: style_handle })
        @result = JSON(oauth2_response.body)
      end
    end

    def login # 未登录时提示用户登录或者注册(如果直接跳转至登录页面则对未注册用户不友好)
    end

    def logout
      session[:shop] = nil
      session[:shop_url] = nil
      redirect_to theme_path(handle: handle, style_handle: style_handle)
    end

    def authenticate # 跳转至用户商店的认证登录页面oauth
      session[:shop_url] ||= params[:shop_url] # 如果后台管理已经设置了商店url
      if session[:shop_url] == ""
         session[:shop_url] = nil
         redirect_to theme_store_url_with_port and return
      end
      redirect_to client.auth_code.authorize_url(
        redirect_uri: Theme.client_redirect_uri,
        scope: Theme.client_scope,
      )
    end

    def filter # 查询主题
      session[:q] = request.query_string
      price = params[:price]
      color = params[:color]
      themes =  Theme.order(:position.asc)
      if price == 'free'
        themes = themes.where(:price.eq => 0)
      elsif price == 'paid'
        themes = themes.where(:price.not_eq => 0)
      end
      themes = themes.where(color: color) unless color.blank?
      themes_json = themes.inject([]) do |result, theme|
        result << { theme: theme.attributes }; result
      end.to_json
      render json: themes_json
    end

    def robots
      robots = File.read(Rails.root.join("public/robots/themes_robots.txt"))
      render text: robots, layout: false, content_type: "text/plain"
    end

  end


  protected
  def client
    @client ||= OAuth2::Client.new(
      Theme.client_id,
      Theme.client_secret,
      site: shop_url
    )
  end

  def token
    shop = Shop.at(shop_host)
    Theme.client.access_tokens.find_by_resource_owner_id(shop.id).token
  end

  def authenticate_shop! # 必须通过认证
    redirect_to theme_path(handle: handle, style_handle: style_handle) unless permanent_domain
  end

end
