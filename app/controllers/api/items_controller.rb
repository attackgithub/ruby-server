class Api::ItemsController < Api::ApiController

  require "standard_file"

  def sync_manager
    if !@sync_manager
      version = params[:api]
      if version == "20190520"
        @sync_manager = StandardFile::V20190520::SyncManager.new(current_user)
      else
        @sync_manager = StandardFile::V20161215::SyncManager.new(current_user)
      end
    end
    @sync_manager
  end

  def sync
    options = {
      :sync_token => params[:sync_token],
      :cursor_token => params[:cursor_token],
      :limit => params[:limit],
      :content_type => params[:content_type]
    }
    results = sync_manager.sync(params[:items], options, request)
    post_to_extensions(params.to_unsafe_hash[:items])

    if params[:compute_integrity]
      results[:integrity_hash] = current_user.compute_data_signature
    end

    render :json => results
  end

  def post_to_extensions(items)
    if !items || items.length == 0
      return
    end

    extensions = current_user.items.where(:content_type => "SF|Extension")
    extensions.each do |ext|
      content = ext.decoded_content
      if content
        frequency = content["frequency"]
        subtype = content["subtype"]
        if frequency == "realtime" || (subtype == nil && (frequency == nil || frequency != "daily"))
          post_to_extension(content["url"], items)
        end
      end
    end
  end

  def post_to_extension(url, items)
    if url && url.length > 0
      ExtensionJob.perform_later(url, items, user_manager.auth_params(current_user.email))
    end
  end

  # Writes all user data to backup extension.
  # This is called when a new extension is registered.
  def backup
    ext = current_user.items.find(params[:uuid])
    content = ext.decoded_content
    if content && content["subtype"] == nil
      items = current_user.items.to_a
      if items && items.length > 0
        post_to_extension(content["url"], items)
      end
    end
  end


  ##
  ## REST API
  ##

  def create
    item = current_user.items.new(params[:item].permit(*permitted_params))
    item.save
    render :json => {:item => item}
  end

  def destroy
    ids = params[:uuids] || [params[:uuid]]
    sync_manager.destroy_items(ids)
    render :json => {}, :status => 204
  end

  private

  def permitted_params
    [:content_type, :content, :auth_hash, :enc_item_key]
  end

end
