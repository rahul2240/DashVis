class DashboardController < ApplicationController
  before_action :authenticate_user
  before_action :get_required_data

  include DownloadHelper

  def tables
    download(@df)
  end

  def charts
    @category_columns  = ['Classification-A', 'Classification-B']
    @category_datasets = @category_columns.map do |category_column|
      frequency_hash(@data, @vectors, category_column)
    end
  end

  def settings
    @current_user = current_user

    if request.post?
      @current_user.update(
        name: user_params[:name],
        email: user_params[:email] || @current_user.email,
        image: user_params[:image] || @current_user.image
      )

      flash[:message] = 'Your preferences have been saved succesfully.'
    end
  end

  def datatable_server_side
    compute_datatable_params

    matching_df   = @df unless @datatable[:search]
    matching_df ||= @df.filter_rows { |row| row.to_a.join("\t").downcase.include?(@datatable[:search].downcase) }
    ordered_df    =
      case @datatable[:sort_column]
      when nil, "Action"
        matching_df
      else
        matching_df.sort([@datatable[:sort_column]], ascending: @datatable[:sort_order] == 'asc')
      end

    paginated_df   = ordered_df if ordered_df.nrows == 1
    paginated_df ||= ordered_df.row[@datatable[:start_index]..@datatable[:end_index]]

    html_df = paginated_df
    html_df['Action'] = paginated_df.map_rows_with_index do |row, i|
      table_name = row['Name'].gsub(/<\/?[^>]*>/, "")
      "<a class='text-color delete-table' href='#' data-url='/tables/#{i}/delete' data-name=\"#{table_name}\" data-type='ajax-loader'><i class='material-icons'>delete</i></a></div><a href='/tables/#{i}/edit' class='text-color'><i class='material-icons'>edit</i></a>"
    end
    paginated_df = html_df

    respond_to do |format|
      format.json do
        render json: {
          draw: params['draw'],
          recordsTotal: @df.size,
          recordsFiltered: matching_df.size,
          data: paginated_df.to_json
        }
      end
    end
  end

  def set_color
    @current_user = current_user
    @current_user.update(color_scheme: user_params[:color])
  end

  private

  def frequency_hash(rows, vectors, category)
    col_index = vectors.index(category)
    col       = rows.map { |row| row[col_index]        }
    col.uniq.sort.map    { |ele| [ele, col.count(ele)] }.to_h
  end

  def compute_datatable_params
    @datatable = {
      start_index: params['start'].to_i,
      end_index: params['start'].to_i + params['length'].to_i - 1,
      search: params['search'] ? params['search']['value'] : nil,
      sort_column: params['order'] ? params['columns'][params['order']['0']['column']]['data'] : nil,
      sort_order: params['order']['0']['dir']
    }
  end

  def user_params
    params.permit(:name, :email, :image, :color)
  end

  def authenticate_user
    redirect_to root_path and return unless signed_in?
  end

  def get_required_data
    @df = Daru::DataFrame.new(
      current_user.tables.all.map.with_index do |record, i|
        {
          'SNo'         => i+1,
          'Name'        => "<a href='/tables/#{record.id}'>#{record.name}</a>",
          'Description' => record.description.to_s,
          'Rows'        => record.rows.count,
          'Columns'     => record.columns.count
          # 'Charts'      => record.charts.count
        }
      end,
      index: @current_user.tables.all.map(&:id)
    )
    @vectors = @df.vectors.to_a
  end
end
