Cruddy = window.Cruddy || {}

Cruddy.baseUrl = Cruddy.root + "/" + Cruddy.uri

API_URL = "/backend/api/v1"
TRANSITIONEND = "transitionend webkitTransitionEnd oTransitionEnd otransitionend MSTransitionEnd"
NOT_AVAILABLE = "&mdash;"
moment.lang Cruddy.locale ? "en"

Backbone.emulateHTTP = true
Backbone.emulateJSON = true

#$(document).ajaxError (e, xhr, options) =>
#    location.href = "/login" if xhr.status is 403 and not options.dontRedirect

$(document)
    .ajaxSend (e, xhr, options) ->
        options.displayLoading = no if not Cruddy.app
        Cruddy.app.startLoading() if options.displayLoading

        return

    .ajaxComplete (e, xhr, options) ->
        Cruddy.app.doneLoading() if options.displayLoading

        return

$(document.body)
    .on "click", "[data-trigger=fancybox]", (e) ->
        return no if $.fancybox.open(e.currentTarget) isnt false

        return

$.extend $.fancybox.defaults,
    openEffect: "elastic"
humanize = (id) => id.replace(/_-/, " ")

# Get url for an entity action
entity_url = (id, extra) ->
    url = Cruddy.baseUrl + "/api/" + id;
    url += "/" + extra if extra

    url

# Call callback after browser has taken a breath
after_break = (callback) -> setTimeout callback, 50

# Get thumb link
thumb = (src, width, height) ->
    url = "#{ Cruddy.baseUrl }/thumb?src=#{ encodeURIComponent(src) }"
    url += "&amp;width=#{ width }" if width
    url += "&amp;height=#{ height }" if height

    url

b_icon = (icon) -> "<span class='glyphicon glyphicon-#{ icon }'></span>"

b_btn = (label, icon = null, className = "btn-default", type = 'button') ->
    label = b_icon(icon) + ' ' + label if icon
    className = "btn-" + className.join(" btn-") if _.isArray className

    "<button type='#{ type }' class='btn #{ className }'>#{ label.trim() }</button>"

class Alert extends Backbone.View
    tagName: "span"
    className: "alert"

    initialize: (options) ->
        @$el.addClass @className + "-" + options.type ? "info"
        @$el.text options.message

        setTimeout (=> @remove()), options.timeout if options.timeout?

        this

    render: ->
        after_break => @$el.addClass "show"

        this

    remove: ->
        @$el.one TRANSITIONEND, => super

        @$el.removeClass "show"

        this
class Cruddy.View extends Backbone.View
    componentId: (component) -> @cid + "-" + component

    $component: (component) -> @$ "#" + @componentId(component)
class AdvFormData
    constructor: (data) ->
        @original = new FormData
        @append data if data?

    append: (name, value) ->
        if value is undefined
            value = name
            name = null

        return @original.append name, value if value instanceof File or value instanceof Blob

        if _.isArray value
            return @append name, "" if _.isEmpty value

            @append @key(name, key), _value for _value, key in value

            return

        if _.isObject value
            if _.isFunction value.serialize
                @append name, value.serialize()
                
            else
                @append @key(name, key), _value for key, _value of value

            return

        @original.append name, @process value

    process: (value) ->
        return "" if value is null
        return 1 if value is yes
        return 0 if value is no

        value

    key: (outer, inner) -> if outer then "#{ outer }[#{ inner }]" else inner
class Factory
    create: (name, options) ->
        constructor = @[name]
        return new constructor options if constructor?

        console.error "Failed to resolve #{ name }."

        null
class Attribute extends Backbone.Model

    initialize: (options) ->
        @entity = options.entity

        this

    # Get field's type (i.e. css class name)
    getType: -> @attributes.type

    # Get field's help
    getHelp: -> @attributes.help

    # Get whether a column has complex filter
    canFilter: -> @attributes.filter_type is "complex"

    # Get whether a column is visible
    isVisible: -> @attributes.hide is no
class DataSource extends Backbone.Model
    defaults:
        data: []
        search: ""

    initialize: (attributes, options) ->
        @entity = options.entity
        @columns = options.columns if options.columns?
        @filter = options.filter if options.filter?

        @options =
            url: @entity.url()
            dataType: "json"
            type: "get"
            displayLoading: yes

            success: (resp) =>
                @_hold = true
                @set resp.data
                @_hold = false

                @trigger "data", this, resp.data.data

            error: (xhr) => @trigger "error", this, xhr

        @listenTo @filter, "change", (=>
            @set current_page: 1, silent: yes
            @fetch()
        ) if @filter?

        @on "change", => @fetch() unless @_hold
        @on "change:search", => @set current_page: 1, silent: yes unless @_hold

    hasData: -> not _.isEmpty @get "data"

    hasMore: -> @get("current_page") < @get("last_page")

    isFull: -> !@hasMore()

    inProgress: -> @request?

    holdFetch: ->
        @_hold = yes

        return this

    fetch: ->
        @_hold = no

        @request.abort() if @request?

        @options.data = @data()

        @request = $.ajax @options

        @request.always => @request = null

        @trigger "request", this, @request

        @request

    more: ->
        return if @isFull()

        @set current_page: @get("current_page") + 1, silent: yes

        @fetch()

    data: ->
        data = {
            order_by: @get "order_by"
            order_dir: @get "order_dir"
            page: @get "current_page"
            per_page: @get "per_page"
            keywords: @get "search"
        }

        filters = @filterData()

        data.filters = filters unless _.isEmpty filters
        data.columns = @columns.join "," if @columns?

        data

    filterData: ->
        return null unless @filter?

        data = {}

        for key, value of @filter.attributes
            data[key] = value unless value is null or value is ""

        data
class SearchDataSource extends Backbone.Model
    defaults:
        search: ""

    initialize: (attributes, options) ->
        @filters = new Backbone.Model

        @options =
            url: options.url
            type: "get"
            dataType: "json"

            data:
                simple: 1

            success: (resp) =>
                resp = resp.data

                @data.push item for item in resp.data

                @page = resp.current_page
                @more = resp.current_page < resp.last_page
                @request = null

                @trigger "data", this, @data

                this

            error: (xhr) =>
                @request = null
                @trigger "error", this, xhr

                this

        $.extend yes, @options, options.ajaxOptions if options.ajaxOptions?

        @reset()

        @on "change:search", @refresh, this
        @listenTo @filters, "change", @refresh

        this

    refresh: -> @reset().next()

    reset: ->
        @data = []
        @page = null
        @more = yes

        this

    fetch: (q, page, filters) ->
        @request.abort() if @request?

        $.extend @options.data, 
            page: page
            keywords: q
            filters: filters

        @trigger "request", this, @request = $.ajax @options

        @request

    next: ->
        if @more
            page = if @page? then @page + 1 else 1

            @fetch @get("search"), page, @filters.attributes

        this

    inProgress: -> @request?
class Pagination extends Backbone.View
    tagName: "ul"
    className: "pager"

    events:
        "click a": "navigate"

    initialize: (options) ->
        router = Cruddy.router

        @listenTo @model, "data", @render
        @listenTo @model, "request", @disable

        $(document).on "keydown.pagination", $.proxy this, "hotkeys"

        this

    hotkeys: (e) ->
        if e.ctrlKey and e.keyCode is 37
            @previous()

            return false

        if e.ctrlKey and e.keyCode is 39
            @next()

            return false

        this

    page: (n) ->
        @model.set "current_page", n if n > 0 and n <= @model.get "last_page"

        this

    previous: -> @page @model.get("current_page") - 1

    next: -> @page @model.get("current_page") + 1

    navigate: (e) ->
        e.preventDefault()

        @page $(e.target).data "page" if !@model.inProgress()

    disable: ->
        @$("a").addClass "disabled"

        this

    render: ->
        last = @model.get("last_page")

        @$el.toggle last? and last > 1

        @$el.html @template @model.get("current_page"), last if last > 1

        this

    template: (current, last) ->
        html = ""
        html += @renderLink current - 1, "&larr; #{ Cruddy.lang.prev }", "previous" + if current > 1 then "" else " disabled"
        html += @renderStats() if @model.get("total")?
        html += @renderLink current + 1, "#{ Cruddy.lang.next } &rarr;", "next" + if current < last then "" else " disabled"

        html

    renderStats: -> """<li class="stats"><span>#{ @model.get "from" } - #{ @model.get "to" } / #{ @model.get "total" }</span></li>"""

    renderLink: (page, label, className = "") -> """<li class="#{ className }"><a href="#" data-page="#{ page }">#{ label }</a></li>"""

class DataGrid extends Backbone.View
    tagName: "table"
    className: "table table-hover data-grid"

    events: {
        "click .sortable": "setOrder"
    }

    constructor: (options) ->
        @className += " data-grid-" + options.entity.id

        super

    initialize: (options) ->
        @entity = options.entity
        @columns = @entity.columns.models.filter (col) -> col.isVisible()
        @columns.unshift new Cruddy.Columns.Actions entity: @entity

        @listenTo @model, "data", @updateData
        @listenTo @model, "change:order_by change:order_dir", @onOrderChange

        @listenTo @entity, "change:instance", @onInstanceChange

    onOrderChange: ->
        orderBy = @model.get "order_by"
        orderDir = @model.get "order_dir"

        if @orderBy? and orderBy isnt @orderBy
            @$("#col-#{ @orderBy } .sortable").removeClass "asc desc"

        @orderBy = orderBy
        @$("#col-#{ @orderBy } .sortable").removeClass("asc desc").addClass orderDir

        this

    onInstanceChange: (entity, curr) ->
        prev = entity.previous "instance"

        if prev?
            @$("#item-#{ prev.id }").removeClass "active"
            prev.off null, null, this

        if curr?
            @$("#item-#{ curr.id }").addClass "active"
            curr.on "sync destroy", (=> @model.fetch()), this

        this

    setOrder: (e) ->
        orderBy = $(e.target).data "id"
        orderDir = @model.get "order_dir"

        if orderBy is @model.get "order_by"
            orderDir = if orderDir == 'asc' then 'desc' else 'asc'
        else
            orderDir = @entity.columns.get(orderBy).get "order_dir"

        @model.set { order_by: orderBy, order_dir: orderDir }

        this

    navigate: (e) ->
        Cruddy.router.navigate @entity.link($(e.currentTarget).data "id"), { trigger: true }

        return false

    updateData: (datasource, data) ->
        @$(".items").replaceWith @renderBody @columns, data

        this

    render: ->
        data = @model.get "data"

        @$el.html @renderHead(@columns) + @renderBody(@columns, data)

        @onOrderChange @model

        this

    renderHead: (columns) ->
        html = "<thead><tr>"
        html += @renderHeadCell col for col in columns
        html += "</tr></thead>"

    renderHeadCell: (col) ->
        """<th class="#{ col.getClass() }" id="col-#{ col.id }">#{ @renderHeadCellValue col }</th>"""

    renderHeadCellValue: (col) ->
        title = _.escape col.getHeader()
        help = _.escape col.getHelp()
        title = "<span class=\"sortable\" data-id=\"#{ col.id }\">#{ title }</span>" if col.canOrder()
        if help then "<span class=\"glyphicon glyphicon-question-sign\" title=\"#{ help }\"></span> #{ title }" else title

    renderBody: (columns, data) ->
        html = "<tbody class=\"items\">"

        if data? and data.length
            html += @renderRow columns, item for item in data
        else
            html += """<tr><td class="no-items" colspan="#{ columns.length }">#{ Cruddy.lang.no_results }</td></tr>"""

        html += "</tbody>"

    renderRow: (columns, item) ->
        html = "<tr class=\"item #{ @states item }\" id=\"item-#{ item.id }\" data-id=\"#{ item.id }\">"
        html += @renderCell col, item for col in columns
        html += "</tr>"

    states: (item) -> 
        states = if item._states then item._states else ""

        states += " active" if (instance = @entity.get "instance")? and item.id == instance.id

        return states

    renderCell: (col, item) ->
        """<td class="#{ col.getClass() }">#{ col.render item }</td>"""
class FilterList extends Backbone.View
    className: "filter-list"

    tagName: "fieldset"

    events:
        "click .btn-apply": "apply"
        "click .btn-reset": "reset"

    initialize: (options) ->
        @entity = options.entity
        @availableFilters = options.filters
        @filterModel = new Backbone.Model

        @listenTo @model, "change", (model) -> @filterModel.set model.attributes

        this

    apply: ->
        @model.set @filterModel.attributes

        return this

    reset: ->
        input.empty() for input in @filters

        @apply()

    render: ->
        @dispose()

        @$el.html @template()
        @items = @$ ".filter-list-container"

        for filter in @availableFilters when (field = @entity.fields.get filter) and field.canFilter() and (input = field.createFilterInput @filterModel)
            @filters.push input
            @items.append input.render().el
            input.$el.wrap("""<div class="form-group filter filter-#{ field.id }"></div>""").parent().before "<label>#{ field.getFilterLabel() }</label>"

        this

    template: -> """
        <div class="filter-list-container"></div>
        <button type="button" class="btn btn-primary btn-apply">#{ Cruddy.lang.filter_apply }</button>
        <button type="button" class="btn btn-default btn-reset">#{ Cruddy.lang.filter_reset }</button>
    """

    dispose: ->
        filter.remove() for filter in @filters if @filters?

        @filters = []

        this

    remove: ->
        @dispose()

        super
Cruddy.Inputs = {}

# Base class for input that will be bound to a model's attribute.
class Cruddy.Inputs.Base extends Cruddy.View
    constructor: (options) ->
        @key = options.key

        super

    initialize: ->
        @listenTo @model, "change:" + @key, (model, value, options) ->
            @applyChanges value, not options.input or options.input isnt this

        this

    # Apply changes when model's attribute changed.
    # external is true when value is changed not by input itself.
    applyChanges: (data, external) -> this

    render: ->
        @applyChanges @getValue(), yes

    # Focus an element.
    focus: -> this

    # Get current value.
    getValue: -> @model.get @key

    # Set current value.
    setValue: (value, options = {}) ->
        options.input = this

        @model.set @key, value, options

        this

    emptyValue: -> null

    empty: -> @model.set @key, @emptyValue()
# Renders formatted text and doesn't have any editing features.
class Cruddy.Inputs.Static extends Cruddy.Inputs.Base
    tagName: "p"
    className: "form-control-static"

    initialize: (options) ->
        @formatter = options.formatter if options.formatter?

        super

    applyChanges: (data) -> @render()

    render: ->
        value = @getValue()
        value = @formatter.format value if @formatter?

        @$el.html value

        this
class Cruddy.Inputs.BaseText extends Cruddy.Inputs.Base
    className: "form-control"

    events:
        "change": "change"
        "keydown": "keydown"

    keydown: (e) ->
        # Ctrl + Enter
        return @change() if e.ctrlKey and e.keyCode is 13

        this

    disable: ->
        @$el.prop "disabled", yes

        this

    enable: ->
        @$el.prop "disabled", no

        this

    change: -> @setValue @el.value

    applyChanges: (data, external) ->
        @$el.val data if external

        this

    focus: ->
        @el.focus()

        this
        
# Renders an <input> value of which is bound to a model's attribute.
class Cruddy.Inputs.Text extends Cruddy.Inputs.BaseText
    tagName: "input"

    initialize: (options) ->
        # Apply mask
        options.mask and @$el.mask options.mask

        super

# Renders a <textarea> input.
class Cruddy.Inputs.Textarea extends Cruddy.Inputs.BaseText
    tagName: "textarea"
# Renders a checkbox
class Cruddy.Inputs.Checkbox extends Cruddy.Inputs.Base
    tagName: "label"
    label: ""

    events:
        "change": "change"

    initialize: (options) ->
        @label = options.label if options.label?

        super

    change: -> @setValue @input.prop "checked"

    applyChanges: (value, external) ->
        @input.prop "checked", value if external

        this

    render: ->
        @input = $ "<input>", { type: "checkbox", checked: @getValue() }
        @$el.append @input
        @$el.append @label if @label?

        this
class Cruddy.Inputs.Boolean extends Cruddy.Inputs.Base
    events:
        "click .btn": "check"

    initialize: (options) ->
        @tripleState = options.tripleState ? false

        super

    check: (e) ->
        value = !!$(e.target).data "value"
        currentValue = @model.get @key

        value = null if value == currentValue and @tripleState

        @setValue value

    applyChanges: (value) ->
        value = switch value
            when yes then 0
            when no then 1
            else null

        @values.removeClass("active")
        @values.eq(value).addClass "active" if value?

        this

    render: ->
        @$el.html @template()

        @values = @$ ".btn"

        super

    template: ->
        """
        <div class="btn-group">
            <button type="button" class="btn btn-default" data-value="1">#{ Cruddy.lang.yes }</button>
            <button type="button" class="btn btn-default" data-value="0">#{ Cruddy.lang.no }</button>
        </div>
        """

    focus: ->
        @values?[0].focus()

        this
class Cruddy.Inputs.EntityDropdown extends Cruddy.Inputs.Base
    className: "entity-dropdown"

    events:
        "click .ed-item>.input-group-btn>.btn-remove": "removeItem"
        "click .ed-item>.input-group-btn>.btn-edit": "editItem"
        "click .ed-item>.form-control": "executeFirstAction"
        "keydown .ed-item>.form-control": "itemKeydown"
        "keydown [type=search]": "searchKeydown"
        "show.bs.dropdown": "renderDropdown"

        "shown.bs.dropdown": ->
            after_break => @selector.focus()

            this

        "hide.bs.dropdown": (e) ->
            e.preventDefault() if @executingFirstAction

            return

        "hidden.bs.dropdown": ->
            @opened = no

            this

    initialize: (options) ->
        @multiple = options.multiple if options.multiple?
        @reference = options.reference if options.reference?
        @owner = options.owner if options.owner?

        # Whether to show edit button (pencil)
        @allowEdit = options.allowEdit ? yes and @reference.updatePermitted()

        @placeholder = options.placeholder ? Cruddy.lang.not_selected

        # Whether the drop down is enabled
        @enabled = options.enabled ? true

        # Whether the item is currently editing
        @editing = false

        # Whether to not allow to open a dropdown
        @disableDropdown = false

        # Whether the dropdown is opened
        @opened = false

        if options.constraint
            @constraint = options.constraint
            @listenTo @model, "change:" + @constraint.field, -> @checkToDisable().applyConstraint yes

        super

    getKey: (e) -> $(e.currentTarget).closest(".ed-item").data "key"

    removeItem: (e) ->
        if @multiple
            i = @getKey e
            value = _.clone @model.get(@key)
            value.splice i, 1
        else
            value = null

        @setValue value

    executeFirstAction: (e) ->
        $(".btn:not(:disabled):last", $(e.currentTarget).next()).trigger "click"

        return false

    editItem: (e) ->
        return if @editing or not @allowEdit

        item = @model.get @key
        item = item[@getKey e] if @multiple

        return if not item

        btn = $(e.currentTarget)

        # We'll look for the button if it is form control that was clicked
        btn = btn.next().children(".btn-edit") if btn.is ".form-control"

        btn.prop "disabled", yes

        @editing = @reference.load(item.id).done (instance) =>
            @innerForm = new Cruddy.Entity.Form
                model: instance
                inner: yes

            @innerForm.render().$el.appendTo document.body
            after_break => @innerForm.show()

            @listenTo instance, "sync", (model, resp) =>
                # Check whether the model was destroyed
                if resp.data
                    btn.parent().siblings("input").val resp.data.title
                    @innerForm.remove()
                else
                    @removeItem e

            @listenTo @innerForm, "remove", => @innerForm = null

        @editing.always =>
            @editing = no
            btn.prop "disabled", no

        this

    searchKeydown: (e) ->
        if (e.keyCode is 27)
            @$el.dropdown "toggle"
            return false

        return

    itemKeydown: (e) ->
        if (e.keyCode is 13)
            @executeFirstAction e
            return false

        return

    applyConstraint: (reset = no) ->
        if @selector
            value = @model.get @constraint.field
            @selector.dataSource?.filters.set @constraint.otherField, value
            @selector.createAttributes[@constraint.otherField] = value

        @model.set(@key, if @multiple then [] else null) if reset

        this

    checkToDisable: ->
        if not @enabled or @constraint and _.isEmpty(@model.get @constraint.field) then @disable() else @enable()

        this

    disable: ->
        return this if @disableDropdown

        @disableDropdown = yes

        @toggleDisableControls()

    enable: ->
        return this if not @disableDropdown

        @disableDropdown = no

        @toggleDisableControls()

    toggleDisableControls: ->
        @dropdownBtn.prop "disabled", @disableDropdown
        @$el.toggleClass "disabled", @disableDropdown

        this

    renderDropdown: (e) ->
        if @disableDropdown
            e.preventDefault()

            return

        @opened = yes

        if not @selector
            @selector = new Cruddy.Inputs.EntitySelector
                model: @model
                key: @key
                multiple: @multiple
                reference: @reference
                allowCreate: @allowEdit
                owner: @owner

            @applyConstraint() if @constraint

            @$el.append @selector.render().el

        dataSource = @selector.dataSource

        dataSource.refresh() if not dataSource.inProgress()

        @toggleOpenDirection()

    toggleOpenDirection: ->
        return if not @opened

        wnd = $(window)
        space = wnd.height() - @$el.offset().top - wnd.scrollTop() - @$el.parent(".field-list").scrollTop()

        targetClass = if space > 292 then "open-down" else "open-up"

        @$el.removeClass("open-up open-down").addClass targetClass if not @$el.hasClass targetClass

        this

    applyChanges: (value) ->
        if @multiple
            @renderItems()
        else
            @updateItem()
            @$el.removeClass "open"

        @toggleOpenDirection()

        this

    render: ->
        @dispose()

        if @multiple then @renderMultiple() else @renderSingle()

        @dropdownBtn = @$ "##{ @cid }-dropdown"

        @$el.attr "id", @cid

        @checkToDisable()

        this

    renderMultiple: ->
        @$el.append @items = $ "<div>", class: "items"

        @$el.append """
            <button type="button" class="btn btn-default btn-block dropdown-toggle ed-dropdown-toggle" data-toggle="dropdown" id="#{ @cid }-dropdown" data-target="##{ @cid }">
                #{ Cruddy.lang.choose }
                <span class="caret"></span>
            </button>
            """ if @enabled

        @renderItems()

    renderItems: ->
        html = ""
        html += @itemTemplate value.title, key for value, key in @getValue()
        @items.html html
        @items.toggleClass "has-items", html isnt ""

        this

    renderSingle: ->
        @$el.html @itemTemplate "", "0"

        @itemTitle = @$ ".form-control"
        @itemDelete = @$ ".btn-remove"
        @itemEdit = @$ ".btn-edit"

        @updateItem()

    updateItem: ->
        value = @getValue()

        @itemTitle.val if value then value.title else ""

        @itemDelete.toggle !!value
        @itemEdit.toggle !!value

        this

    itemTemplate: (value, key = null) ->
        html = """
            <div class="input-group ed-item #{ if not @multiple then "ed-dropdown-toggle" else "" }" data-key="#{ key }">
                <input type="text" class="form-control" #{ if @multiple then "tab-index='-1'" else "placeholder='#{ @placeholder }'" } value="#{ _.escape value }" readonly>
            """

        html += """
            <div class="input-group-btn">
                #{ buttons }
            </div>
            """ if not _.isEmpty buttons = @buttonsTemplate()

        html += "</div>"

    buttonsTemplate: ->
        html = ""

        html += """
            <button type="button" class="btn btn-default btn-remove" tabindex="-1">
                <span class="glyphicon glyphicon-remove"></span>
            </button>
            """ if @enabled

        html += """
            <button type="button" class="btn btn-default btn-edit" tabindex="-1">
                <span class="glyphicon glyphicon-pencil"></span>
            </button>
            """ if @allowEdit

        html += """
            <button type="button" class="btn btn-default btn-dropdown dropdown-toggle" data-toggle="dropdown" id="#{ @cid }-dropdown" data-target="##{ @cid }" tab-index="1">
                <span class="glyphicon glyphicon-search"></span>
            </button>
            """ if not @multiple

        html

    focus: ->
        $el = @$component("dropdown")
        $el = $el.parent().prev() if not @multiple

        $el[0].focus()

        $el.trigger("click") if _.isEmpty @getValue()

        this

    emptyValue: -> if @multiple then [] else null

    dispose: ->
        @selector?.remove()
        @innerForm?.remove()

        this

    remove: ->
        @dispose()

        super
class Cruddy.Inputs.EntitySelector extends Cruddy.Inputs.Base
    className: "entity-selector"

    events:
        "click .item": "check"
        "click .more": "more"
        "click .btn-add": "add"
        "click [type=search]": -> false

    initialize: (options) ->
        super

        @filter = options.filter ? false
        @multiple = options.multiple ? false
        @reference = options.reference

        @allowSearch = options.allowSearch ? yes
        @allowCreate = options.allowCreate ? yes and @reference.createPermitted()

        @createAttributes = {}

        @data = []
        @buildSelected @model.get @key

        if @reference.viewPermitted()
            @primaryKey = "id"

            @dataSource = @reference.search ajaxOptions: data: owner: options.owner

            @listenTo @dataSource, "request", @loading
            @listenTo @dataSource, "data",    @renderItems
            @listenTo @dataSource, "error",   @displayError

        this

    checkForMore: ->
        @more() if @moreElement? and @items.parent().height() + 50 > @moreElement.position().top

        this

    check: (e) ->
        id = $(e.target).data("id").toString()
        @select _.find @dataSource.data, (item) -> item.id.toString() == id

        false

    select: (item) ->
        if @multiple
            if item.id of @selected
                value = _.filter @model.get(@key), (item) -> item.id != id
            else
                value = _.clone @model.get(@key)
                value.push item
        else
            value = item

        @setValue value

    more: ->
        return if not @dataSource or @dataSource.inProgress()

        @dataSource.next()

        false

    add: (e) ->
        e.preventDefault()
        e.stopPropagation()

        instance = @reference.createInstance attributes: @createAttributes

        @innerForm = new Cruddy.Entity.Form
            model: instance
            inner: yes

        @innerForm.render().$el.appendTo document.body
        after_break => @innerForm.show()

        @listenToOnce @innerForm, "remove", => @innerForm = null

        @listenToOnce instance, "sync", (instance, resp) =>
            @select
                id: instance.id
                title: resp.data.title

            @dataSource.set "search", ""
            @innerForm.remove()

        this

    applyChanges: (data) ->
        @buildSelected data
        @renderItems()

    buildSelected: (data) ->
        @selected = {}

        if @multiple
            @selected[item.id] = yes for item in data
        else
            @selected[data.id] = yes if data?

        this

    loading: ->
        @moreElement?.addClass "loading"

        this

    renderItems: ->
        @moreElement = null

        html = ""

        if @dataSource.data.length or @dataSource.more
            html += @renderItem item for item in @dataSource.data

            html += """<li class="more #{ if @dataSource.inProgress() then "loading" else "" }">#{ Cruddy.lang.more }</li>""" if @dataSource.more
        else
            html += "<li class='empty'>#{ Cruddy.lang.no_results }</li>"

        @items.html html

        if @dataSource.more
            @moreElement = @items.children ".more"
            @checkForMore()

        this

    renderItem: (item) ->
        className = if item.id of @selected then "selected" else ""

        """<li class="item #{ className }" data-id="#{ item.id }">#{ item.title }</li>"""

    render: ->
        if @reference.viewPermitted()
            @dispose()

            @$el.html @template()

            @items = @$ ".items"

            @renderItems()

            @items.parent().on "scroll", $.proxy this, "checkForMore"

            @renderSearch() if @allowSearch
        else
            @$el.html "<span class=error>#{ Cruddy.lang.forbidden }</span>"

        this

    renderSearch: ->
        @searchInput = new Cruddy.Inputs.Search
            model: @dataSource
            key: "search"

        @$el.prepend @searchInput.render().$el

        @searchInput.$el.wrap "<div class=search-input-container></div>"

        @searchInput.appendButton """
            <button type="button" class='btn btn-default btn-add' tabindex='-1'>
                <span class='glyphicon glyphicon-plus'></span>
            </button>
        """ if @allowCreate

        this

    template: -> """<div class="items-container"><ul class="items"><li class="more loading"></li></ul></div>"""

    focus: ->
        @searchInput?.focus() or @entity.done => @searchInput.focus()

        this

    dispose: ->
        @searchInput?.remove()
        @innerForm?.remove()

        this

    remove: ->
        @dispose()

        super

class Cruddy.Inputs.FileList extends Cruddy.Inputs.Base
    className: "file-list"

    events:
        "change [type=file]": "appendFiles"
        "click .action-delete": "deleteFile"

    initialize: (options) ->
        @multiple = options.multiple ? false
        @formatter = options.formatter ? format: (value) -> if value instanceof File then value.name else value
        @accepts = options.accepts ? ""
        @counter = 1

        super

    deleteFile: (e) ->
        if @multiple
            cid = $(e.currentTarget).data("cid")
            @setValue _.reject @getValue(), (item) => @itemId(item) is cid
        else
            @setValue null

        false

    appendFiles: (e) ->
        return if e.target.files.length is 0

        file.cid = @cid + "_" + @counter++ for file in e.target.files        

        if @multiple
            value = _.clone @model.get @key

            value.push file for file in e.target.files
        else
            value = e.target.files[0]

        @setValue value

    applyChanges: -> @render()

    render: ->
        value = @model.get @key

        html = ""
        html += @renderItem item for item in if @multiple then value else [ value ]
        html = @wrapItems html if html

        html += @renderInput if @multiple then "<span class='glyphicon glyphicon-plus'></span> #{ Cruddy.lang.add }" else Cruddy.lang.choose

        @$el.html html

        this

    wrapItems: (html) -> """<ul class="list-group">#{ html }</ul>"""

    renderInput: (label) ->
        """
        <div class="btn btn-sm btn-default file-list-input-wrap">
            <input type="file" id="#{ @componentId "input" }" accept="#{ @accepts }"#{ if @multiple then " multiple" else "" }>
            #{ label }
        </div>
        """

    renderItem: (item) ->
        label = @formatter.format item

        """
        <li class="list-group-item">
            <a href="#" class="action-delete pull-right" data-cid="#{ @itemId(item) }"><span class="glyphicon glyphicon-remove"></span></a>

            #{ label }
        </li>
        """

    itemId: (item) -> if item instanceof File then item.cid else item

    focus: ->
        @$component("input")[0].focus()

        this


class Cruddy.Inputs.ImageList extends Cruddy.Inputs.FileList
    className: "image-list"

    constructor: ->
        @readers = []

        super

    initialize: (options) ->
        @width = options.width ? 0
        @height = options.height ? 80

        super

    render: ->
        super

        reader.readAsDataURL reader.item for reader in @readers
        @readers = []

        this

    wrapItems: (html) -> """<ul class="image-group">#{ html }</ul>"""

    renderItem: (item) ->
        """
        <li class="image-group-item">
            #{ @renderImage item }
            <a href="#" class="action-delete" data-cid="#{ @itemId(item) }"><span class="glyphicon glyphicon-remove"></span></a>
        </li>
        """

    renderImage: (item) ->
        if isFile = item instanceof File
            image = item.data or ""
            @readers.push @createPreviewLoader item if not item.data?
        else
            image = thumb item, @width, @height

        """
        <a href="#{ if isFile then item.data or "#" else Cruddy.root + '/' + item }" class="img-wrap" data-trigger="fancybox">
            <img src="#{ image }" #{ if isFile then "id='"+item.cid+"'" else "" }>
        </a>
        """

    createPreviewLoader: (item) ->
        reader = new FileReader
        reader.item = item
        reader.onload = (e) ->
            e.target.item.data = e.target.result
            $("#" + item.cid).attr("src", e.target.result).parent().attr "href", e.target.result

        reader
# Search input implements "change when type" and also allows to clear text with Esc
class Cruddy.Inputs.Search extends Cruddy.View
    className: "input-group"

    events:
        "click .btn": "search"

    initialize: (options) ->
        @input = new Cruddy.Inputs.Text
            model: @model
            key: options.key
            attributes:
                type: "search"
                placeholder: Cruddy.lang.search

        super

    search: -> @input.change()

    appendButton: (btn) -> @$btns.append btn

    render: ->
        @$el.append @input.render().$el
        @$el.append @$btns = $ """<div class="input-group-btn"></div>"""

        @appendButton """
            <button type="button" class="btn btn-default">
                <span class="glyphicon glyphicon-search"></span>
            </button>
        """

        return this

    focus: ->
        @input.focus()

        return this
class Cruddy.Inputs.Slug extends Backbone.View
    events:
        "click .btn": "toggleSyncing"

    constructor: (options) ->
        @input = new Cruddy.Inputs.Text _.clone options

        options.className ?= "input-group"

        delete options.attributes if options.attributes?

        super

    initialize: (options) ->
        chars = options.chars ? "a-z0-9\-_"

        @regexp = new RegExp "[^#{ chars }]+", "g"
        @separator = options.separator ? "-"

        @key = options.key
        @ref = if _.isArray(options.ref) then options.ref else [options.ref] if options.ref

        super

    toggleSyncing: ->
        if @syncButton.hasClass "active" then @unlink() else @link()

        this

    link: ->
        return if not @ref

        @listenTo @model, "change:" + @ref.join(" change:"), @sync
        @syncButton.addClass "active"
        @input.disable()

        @sync()

    unlink: ->
        @stopListening @model, null, @sync if @ref?
        @syncButton.removeClass "active"
        @input.enable()

        this

    linkable: ->
        modelValue = @model.get @key
        value = @getValue()

        value == modelValue or modelValue is null and value is ""

    convert: (value) -> if value then value.toLocaleLowerCase().replace(/\s+/g, @separator).replace(@regexp, "") else value

    sync: ->
        @model.set @key, @getValue()

        this

    getValue: ->
        components = []

        for key in @ref
            refValue = @model.get key
            components.push refValue if refValue

        if components.length then @convert components.join @separator else ""

    render: ->
        @$el.html @template()
        @$el.prepend @input.render().el

        if @ref?
            @syncButton = @$ ".btn"
            @link() if @linkable()

        this

    template: ->
        return "" if not @ref?

        """
        <div class="input-group-btn">
            <button type="button" tabindex="-1" class="btn btn-default" title="#{ Cruddy.lang.slug_sync }"><span class="glyphicon glyphicon-link"></span></button>
        </div>
        """
class Cruddy.Inputs.Select extends Cruddy.Inputs.Text
    tagName: "select"

    initialize: (options) ->
        @items = options.items ? {}
        @prompt = options.prompt ? null
        @required = options.required ? no

        super

    applyChanges: (data, external) ->
        @$(":nth-child(#{ @optionIndex data })").prop "selected", yes if external

        this

    optionIndex: (value) ->
        index = if @hasPrompt() then 2 else 1

        for data, label of @items
            break if value == data

            index++

        index

    render: ->
        @$el.html @template()

        @setValue @$el.val() if @required and not @getValue()

        super

    template: ->
        html = ""
        html += @optionTemplate "", @prompt ? Cruddy.lang.not_selected, @required if @hasPrompt()
        html += @optionTemplate key, value for key, value of @items
        html

    optionTemplate: (value, title, disabled = no) ->
        """<option value="#{ _.escape value }"#{ if disabled then " disabled" else ""}>#{ _.escape title }</option>"""

    hasPrompt: -> not @required or @prompt?
class Cruddy.Inputs.Code extends Cruddy.Inputs.Base
    initialize: (options) ->
        @$el.height (options.height ? 100) + "px"

        @editor = ace.edit @el
        @editor.setTheme "ace/theme/#{ options.theme ? Cruddy.ace_theme }"

        session = @editor.getSession()

        session.setMode "ace/mode/#{ options.mode }" if options.mode
        session.setUseWrapMode true
        session.setWrapLimitRange null, null

        super

    applyChanges: (value, external) ->
        if external
            @editor.setValue value
            @editor.getSession().getSelection().clearSelection()

        this

    render: ->
        @editor.on "blur", => @model.set @key, @editor.getValue(), input: @

        super

    remove: ->
        @editor?.destroy()
        @editor = null

        super

    focus: ->
        @editor?.focus()

        this
class Cruddy.Inputs.Markdown extends Cruddy.Inputs.Base

    events:
        "show.bs.tab [data-toggle=tab]": "showTab"
        "shown.bs.tab [data-toggle=tab]": "shownTab"

    initialize: (options) ->
        @height = options.height ? 200

        @editorInput = new Cruddy.Inputs.Code
            model: @model
            key: @key
            theme: options.theme
            mode: "markdown"
            height: @height

        super

    showTab: (e) ->
        @renderPreview() if $(e.target).data("tab") is "preview"

        this

    shownTab: (e) ->
        @editorInput.focus() if $(e.traget).data("tab") is "editor"

    render: ->
        @$el.html @template()

        @$(".tab-pane-editor").append @editorInput.render().el

        @preview = @$ ".tab-pane-preview"

        this

    renderPreview: ->
        @preview.html marked @getValue()

        this

    template: ->
        """
        <div class="markdown-editor">
            <a href="https://help.github.com/articles/github-flavored-markdown" target="_blank" class="hint">GitHub flavored markdown</a>

            <ul class="nav nav-tabs">
                <li class="active"><a href="##{ @cid }-editor" data-toggle="tab" data-tab="editor" tab-index="-1">#{ Cruddy.lang.markdown_source }</a></li>
                <li><a href="##{ @cid }-preview" data-toggle="tab" data-tab="preview" tab-index="-1">#{ Cruddy.lang.markdown_parsed }</a></li>
            </ul>

            <div class="tab-content">
                <div class="tab-pane-editor tab-pane active" id="#{ @cid }-editor"></div>
                <div class="tab-pane-preview tab-pane" id="#{ @cid }-preview" style="height:#{ @height }px"></div>
            </div>
        </div>
        """

    focus: ->
        tab = @$ "[data-tab=editor]"
        if tab.hasClass "active" then @editorInput.focus() else tab.tab "show"

        this
class Cruddy.Inputs.NumberFilter extends Cruddy.Inputs.Base
    className: "input-group number-filter"

    events:
        "click .dropdown-menu a": "changeOperator"
        "change": "changeValue"

    initialize: ->
        @defaultOp = "="

        @setValue @emptyValue(), silent: yes if not @getValue()

        super

    changeOperator: (e) ->
        e.preventDefault()

        op = $(e.currentTarget).data "op"
        value = @getValue()

        @setValue @makeValue op, value.val if value.op isnt op

        this

    changeValue: (e) ->
        value = @getValue()

        @setValue @makeValue value.op, e.target.value

        this

    applyChanges: (value, external) ->
        @$(".dropdown-menu li").removeClass "active"
        @$(".dropdown-menu a[data-op='#{ value.op }']").parent().addClass "active"

        @op.text value.op
        @input.val value.val if external

        this

    render: ->
        @$el.html @template()

        @op = @$component "op"
        @input = @$component "input"
        @reset = @$component "reset"

        super

    template: -> """
        <div class="input-group-btn">
            <button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown">
                <span id="#{ @componentId("op") }" class="value">=</span>
                <span class="caret"></span>
            </button>

            <ul class="dropdown-menu">
                <li><a href="#" data-op="=">=</a></li>
                <li><a href="#" data-op="&gt;">&gt;</a></li>
                <li><a href="#" data-op="&lt;">&lt;</a></li>
            </ul>
        </div>

        <input type="text" class="form-control" id="#{ @componentId "input" }">
    """

    makeValue: (op, val) -> { op: op, val: val }

    emptyValue: -> @makeValue @defaultOp, ""
class Cruddy.Inputs.DateTime extends Cruddy.Inputs.BaseText
    tagName: "input"

    initialize: (options) ->
        @format = options.format

        @$el.mask options.mask if options.mask?

        super

    applyChanges: (value, external) ->
        @$el.val if value is null then "" else moment.unix(value).format @format if external

        this

    change: ->
        value = @$el.val()
        value = if _.isEmpty value then null else moment(value, @format).unix()

        @setValue value

        # We will always set input value because it may not be always parsed properly
        @applyChanges value, yes
Cruddy.Layout = {}

class Cruddy.Layout.Element extends Cruddy.View

    constructor: (options, parent) ->
        @parent = parent
        @disable = options.disable ? no

        super

    initialize: ->
        @model = @parent.model if not @model and @parent
        @entity = @model.entity if @model

        super

    handleValidationError: (error) ->
        @parent.handleValidationError error if @parent

        return this

    isDisabled: ->
        return yes if @disable
        return @parent.isDisabled() if @parent

        return no

    # Get whether element is focusable
    isFocusable: -> no

    # Focus the element
    focus: -> return this
class Cruddy.Layout.Container extends Cruddy.Layout.Element

    initialize: (options) ->
        super

        @$container = @$el
        @items = []

        @createItems options.items if options.items

        return this

    create: (options) ->
        constructor = Cruddy.Layout[options.class]

        if not constructor or not _.isFunction constructor
            console.error "Couldn't resolve element of type ", method 

            return

        @append new constructor options, this

    createItems: (items) ->
        @create item for item in items

        this

    append: (element) ->
        @items.push element if element

        return element

    renderElement: (element) ->
        @$container.append element.render().$el

        return this

    render: ->
        @renderElement element for element in @items if @items

        super

    remove: ->
        item.remove() for item in @items

        super

    getFocusable: -> _.find @items, (item) -> item.isFocusable()

    isFocusable: -> return @getFocusable()?

    focus: ->
        el.focus() if el = @getFocusable()

        return this
class Cruddy.Layout.BaseFieldContainer extends Cruddy.Layout.Container

    constructor: (options) ->
        @title = options.title ? null

        super
class Cruddy.Layout.Fieldset extends Cruddy.Layout.BaseFieldContainer
    tagName: "fieldset"

    render: ->
        @$el.html @template()

        @$container = @$component "body"

        super

    template: ->
        html = if @title then "<legend>" + _.escape(@title) + "</legend>" else ""

        return html + "<div id='" + @componentId("body") + "'></div>"
class Cruddy.Layout.TabPane extends Cruddy.Layout.BaseFieldContainer
    className: "tab-pane"

    initialize: (options) ->
        super

        @title = @entity.get("title").singular if not options.title
        
        @$el.attr "id", @cid

        @listenTo @model, "request", -> @header.resetErrors() if @header

        return this

    activate: ->
        @header?.activate()

        after_break => @focus()

        return this

    getHeader: ->
        @header = new Cruddy.Layout.TabPane.Header model: this if not @header

        return @header

    handleValidationError: ->
        @header?.incrementErrors()

        super

class Cruddy.Layout.TabPane.Header extends Cruddy.View
    tagName: "li"

    events:
        "shown.bs.tab": ->
            after_break => @model.focus()

            return

    initialize: ->
        @errors = 0

        super

    incrementErrors: ->
        @$badge.text ++@errors

        return this

    resetErrors: ->
        @errors = 0
        @$badge.text ""

        return this

    render: ->
        @$el.html @template()

        @$badge = @$component "badge"

        super

    template: -> """
        <a href="##{ @model.cid }" role="tab" data-toggle="tab">
            #{ @model.title }
            <span class="badge" id="#{ @componentId "badge" }"></span>
        </a>"""

    activate: ->
        @$("a").tab("show")

        return this
class Cruddy.Layout.Row extends Cruddy.Layout.Container
    className: "row"
class Cruddy.Layout.Col extends Cruddy.Layout.BaseFieldContainer

    initialize: (options) ->
        @$el.addClass "col-xs-" + options.span

        super
class Cruddy.Layout.Field extends Cruddy.Layout.Element

    initialize: (options) ->
        super

        @fieldView = null

        if not @field = @entity.field options.field
            console.error "The field #{ options.field } is not found in #{ @entity.id }."

        return this

    render: ->
        if @field and @field.isVisible()
            @fieldView = @field.createView @model, @isDisabled(), this

        @$el.html @fieldView.render().$el if @fieldView

        return this

    remove: ->
        @fieldView.remove() if @fieldView

        super

    isFocusable: -> @fieldView and @fieldView.isFocusable()

    focus: ->
        @fieldView.focus() if @fieldView

        return this
class Cruddy.Layout.Text extends Cruddy.Layout.Element
    tagName: "p"
    className: "text-node"

    initialize: (options) ->
        @$el.html options.contents if options.contents

        super
# Displays a list of entity's fields
class FieldList extends Cruddy.Layout.BaseFieldContainer
    className: "field-list"

    initialize: ->
        super

        for field in @entity.fields.models
            @create { class: "Field", field: field.id }

        return this
class Cruddy.Layout.Layout extends Cruddy.Layout.Container

    initialize: ->
        super

        @setupLayout()

    setupLayout: ->
        if @entity.attributes.layout
            @createItems @entity.attributes.layout
        else
            @setupDefaultLayout()

        return this

    setupDefaultLayout: -> return this
Cruddy.Fields = new Factory

class Cruddy.Fields.BaseView extends Cruddy.Layout.Element

    constructor: (options) ->
        @field = field = options.field

        inputId = options.model.entity.id + "__" + field.id
        @inputId = inputId + "__" + options.model.cid

        base = " field-"
        classes = [ field.getType(), field.id, inputId ]
        className = "field" + base + classes.join base

        className += " form-group"

        @className = if @className then className + " " + @className else className

        @forceDisable = options.forceDisable ? false

        super

    initialize: (options) ->
        @listenTo @model, "sync",    @handleSync
        @listenTo @model, "request", @handleRequest
        @listenTo @model, "invalid", @handleInvalid

        @updateContainer()

    handleSync: -> @updateContainer()

    handleRequest: -> @hideError()

    handleInvalid: (model, errors) ->
        if @field.id of errors
            error = errors[@field.id]

            @showError if _.isArray error then _.first error else error

        this

    updateContainer: ->
        @isEditable = not @forceDisable and @field.isEditable(@model)

        @$el.toggle @isVisible()
        @$el.toggleClass "required", @field.isRequired @model

        this

    hideError: ->
        @error.hide()

        this

    showError: (message) ->
        @error.text(message).show()

        @handleValidationError message

        return this

    focus: -> this

    render: ->
        @$(".field-help").tooltip
            container: "body"
            placement: "left"

        @error = @$component "error"

        this

    helpTemplate: ->
        help = @field.getHelp()
        if help then """<span class="glyphicon glyphicon-question-sign field-help" title="#{ _.escape help }"></span>""" else ""

    errorTemplate: -> """<span class="help-block error" style="display:none;" id="#{ @componentId "error" }"></span>"""

    # Get whether the view is visible
    # The field is not visible when model is new and field is not editable or computed
    isVisible: -> @isEditable or not @model.isNew()

    isFocusable: -> @field.isEditable @model

    dispose: -> this

    remove: ->
        @dispose()

        super

# This is basic field view that will render in bootstrap's vertical form style.
class Cruddy.Fields.InputView extends Cruddy.Fields.BaseView

    updateContainer: ->
        isEditable = @isEditable
        
        super

        @render() if isEditable? and isEditable isnt @isEditable


    hideError: ->
        @$el.removeClass "has-error"

        super

    showError: ->
        @$el.addClass "has-error"

        super

    # Render a field
    render: ->
        @dispose()

        @$el.html @template()

        @input = @field.createInput @model, @inputId, @forceDisable

        @$el.append @input.render().el

        @$el.append @errorTemplate()

        super

    label: (label) ->
        label ?= @field.getLabel()
        
        """
        <label for="#{ @inputId }" class="field-label">
            #{ @helpTemplate() }#{ _.escape label }
        </label>
        """

    # The default template that is shown when field is editable.
    template: -> @label()

    # Focus the input that this field view holds.
    focus: ->
        @input.focus()

        this

    dispose: ->
        @input?.remove()

        this

class Cruddy.Fields.Base extends Attribute
    viewConstructor: Cruddy.Fields.InputView

    # Create a view that will represent this field in field list
    createView: (model, forceDisable = no, parent) -> new @viewConstructor { model: model, field: this, forceDisable: forceDisable }, parent

    # Create an input that is used by default view
    createInput: (model, inputId, forceDisable = no) ->
        input = @createEditableInput model, inputId if not forceDisable and @isEditable(model)

        input or @createStaticInput(model)

    # Create an input that will display a static value without possibility to edit
    createStaticInput: (model) -> new Cruddy.Inputs.Static
        model: model
        key: @id
        formatter: this

    # Create an input that is used when field is editable
    createEditableInput: (model, inputId) -> null

    # Create filter input that
    createFilterInput: (model) -> null

    # Get a label for filter input
    getFilterLabel: -> @attributes.label

    # Format value as static text
    format: (value) -> value or NOT_AVAILABLE

    # Get field's label
    getLabel: -> @attributes.label

    # Get whether the field is editable for specified model
    isEditable: (model) -> model.isSaveable() and @attributes.disabled isnt yes and @attributes.disabled isnt model.action()

    # Get whether field is required
    isRequired: (model) -> @attributes.required is yes or @attributes.required == model.action()

    # Get whether the field is unique
    isUnique: -> @attributes.unique
class Cruddy.Fields.Input extends Cruddy.Fields.Base

    createEditableInput: (model, inputId) ->
        input = @createBaseInput model, inputId

        if @attributes.prepend or @attributes.append
            return new Cruddy.Fields.Input.PrependAppendWrapper
                prepend: @attributes.prepend
                append: @attributes.append
                input: input

        return input

    createBaseInput: (model, inputId) -> new Cruddy.Inputs.Text
        model: model
        key: @id
        mask: @attributes.mask
        attributes:
            placeholder: @attributes.placeholder
            id: inputId
            type: @attributes.input_type or "input"

    format: (value) ->
        return NOT_AVAILABLE if value is null or value is ""

        value += " " + @attributes.append if @attributes.append
        value = @attributes.prepend + " " + value if @attributes.prepend

        return value

class Cruddy.Fields.Input.PrependAppendWrapper extends Cruddy.View
    className: "input-group"

    initialize: (options) ->
        @$el.append @createAddon options.prepend if options.prepend
        @$el.append (@input = options.input).$el
        @$el.append @createAddon options.append if options.append

    render: ->
        @input.render()

        return this

    createAddon: (text) -> "<span class=input-group-addon>" + _.escape(text) + "</span>"
class Cruddy.Fields.Text extends Cruddy.Fields.Base

    createEditableInput: (model, inputId) -> new Cruddy.Inputs.Textarea
        model: model
        key: @id
        attributes:
            placeholder: @attributes.placeholder
            id: inputId
            rows: @attributes.rows

    format: (value) -> if value then """<pre class="limit-height">#{ value }</pre>""" else NOT_AVAILABLE
class Cruddy.Fields.BaseDateTime extends Cruddy.Fields.Base

    inputFormat: null
    mask: null

    createEditableInput: (model, inputId) -> new Cruddy.Inputs.DateTime
        model: model
        key: @id
        format: @inputFormat
        mask: @mask
        attributes:
            id: @inputId
    
    format: (value) -> if value is null then NOT_AVAILABLE else moment.unix(value).format(@inputFormat)

class Cruddy.Fields.Date extends Cruddy.Fields.BaseDateTime
    inputFormat: "YYYY-MM-DD"
    mask: "9999-99-99"

class Cruddy.Fields.Time extends Cruddy.Fields.BaseDateTime
    inputFormat: "HH:mm:ss"
    mask: "99:99:99"

class Cruddy.Fields.DateTime extends Cruddy.Fields.BaseDateTime
    inputFormat: "YYYY-MM-DD HH:mm:ss"
    mask: "9999-99-99 99:99:99"
    
    # format: (value) -> if value is null then NOT_AVAILABLE else moment.unix(value).calendar()
class Cruddy.Fields.Boolean extends Cruddy.Fields.Base
    
    createEditableInput: (model) -> new Cruddy.Inputs.Boolean
        model: model
        key: @id

    createFilterInput: (model) -> new Cruddy.Inputs.Boolean
        model: model
        key: @id
        tripleState: yes

    format: (value) -> if value then Cruddy.lang.yes else Cruddy.lang.no
class Cruddy.Fields.BaseRelation extends Cruddy.Fields.Base

    isVisible: -> @getReference().viewPermitted() and super

    # Get the referenced entity
    getReference: ->
        @reference = Cruddy.app.entity @attributes.reference if not @reference

        @reference

    getFilterLabel: -> @getReference().getSingularTitle()

    format: (value) ->
        return NOT_AVAILABLE if _.isEmpty value
        
        if @attributes.multiple then _.pluck(value, "title").join ", " else value.title
class Cruddy.Fields.Relation extends Cruddy.Fields.BaseRelation

    createInput: (model, inputId, forceDisable = no) -> new Cruddy.Inputs.EntityDropdown
        model: model
        key: @id
        multiple: @attributes.multiple
        reference: @getReference()
        owner: @entity.id + "." + @id
        constraint: @attributes.constraint
        enabled: not forceDisable and @isEditable(model)

    createFilterInput: (model) -> new Cruddy.Inputs.EntityDropdown
        model: model
        key: @id
        reference: @getReference()
        allowEdit: no
        placeholder: Cruddy.lang.any_value
        owner: @entity.id + "." + @id
        constraint: @attributes.constraint

    isEditable: -> @getReference().viewPermitted() and super

    canFilter: -> @getReference().viewPermitted() and super
class Cruddy.Fields.File extends Cruddy.Fields.Base

    createEditableInput: (model) -> new Cruddy.Inputs.FileList
        model: model
        key: @id
        multiple: @attributes.multiple
        accepts: @attributes.accepts

    format: (value) -> if value instanceof File then value.name else value
class Cruddy.Fields.Image extends Cruddy.Fields.File

    createEditableInput: (model) -> new Cruddy.Inputs.ImageList
        model: model
        key: @id
        width: @attributes.width
        height: @attributes.height
        multiple: @attributes.multiple
        accepts: @attributes.accepts

    createStaticInput: (model) -> new Cruddy.Inputs.Static
        model: model
        key: @id
        formatter: new Cruddy.Fields.Image.Formatter
            width: @attributes.width
            height: @attributes.height

class Cruddy.Fields.Image.Formatter

    constructor: (options) ->
        @options = options

        return

    imageUrl: (image) -> Cruddy.root + "/" + image

    imageThumb: (image) -> thumb image, @options.width, @options.height

    format: (value) ->
        html = """<ul class="image-group">"""

        value = [ value ] if not _.isArray value

        for image in value
            html += """
                <li class="image-group-item">
                    <a href="#{ @imageUrl image }" class="img-wrap" data-trigger="fancybox">
                        <img src="#{ @imageThumb image }">
                    </a>
                </li>
            """

        return html + "</ul>"
class Cruddy.Fields.Slug extends Cruddy.Fields.Base

    createEditableInput: (model) -> new Cruddy.Inputs.Slug
        model: model
        key: @id
        chars: @attributes.chars
        ref: @attributes.ref
        separator: @attributes.separator
        
        attributes:
            placeholder: @attributes.placeholder
class Cruddy.Fields.Enum extends Cruddy.Fields.Input

    createBaseInput: (model, inputId) -> new Cruddy.Inputs.Select
        model: model
        key: @id
        prompt: @attributes.prompt
        items: @attributes.items
        required: @attributes.required
        attributes:
            id: inputId

    createFilterInput: (model) -> new Cruddy.Inputs.Select
        model: model
        key: @id
        prompt: Cruddy.lang.any_value
        items: @attributes.items

    format: (value) ->
        items = @attributes.items

        if value of items then items[value] else NOT_AVAILABLE
class Cruddy.Fields.Markdown extends Cruddy.Fields.Base

    createEditableInput: (model) -> new Cruddy.Inputs.Markdown
        model: model
        key: @id
        height: @attributes.height
        theme: @attributes.theme

    format: (value) -> if value then "<div class=\"well limit-height\">#{ marked value }</div>" else NOT_AVAILABLE
class Cruddy.Fields.Code extends Cruddy.Fields.Base
    
    createEditableInput: (model) ->
        new Cruddy.Inputs.Code
            model: model
            key: @id
            height: @attributes.height
            mode: @attributes.mode
            theme: @attributes.theme

    format: (value) -> if value then "<div class=\"limit-height\">#{ value }</div>" else NOT_AVAILABLE
class Cruddy.Fields.EmbeddedView extends Cruddy.Fields.BaseView
    className: "has-many-view"

    events:
        "click .btn-create": "create"

    initialize: (options) ->
        @views = {}

        @updateCollection()

        super

    updateCollection: ->
        @stopListening @collection if @collection

        @collection = collection = @model.get @field.id

        @listenTo collection, "add", @add
        @listenTo collection, "remove", @removeItem
        @listenTo collection, "removeSoftly restore", @update

        return this

    handleSync: ->
        super

        @updateCollection()
        @render()

    handleInvalid: (model, errors) ->
        super if @field.id of errors and errors[@field.id].length

        this

    create: (e) ->
        e.preventDefault()
        e.stopPropagation()

        @collection.add @field.getReference().createInstance(), focus: yes

        this

    add: (model, collection, options) ->
        itemOptions =
            model: model
            collection: @collection
            disable: not @isEditable

        @views[model.cid] = view = new Cruddy.Fields.EmbeddedItemView itemOptions, this

        @body.append view.render().el

        after_break( -> view.focus()) if options?.focus

        @focusable = view if not @focusable

        @update()

        this

    removeItem: (model) ->
        if view = @views[model.cid]
            view.remove()
            delete @views[model.cid]

        @update()

        this

    render: ->
        @dispose()

        @$el.html @template()
        @body = @$component "body"
        @createButton = @$ ".btn-create"

        @add model for model in @collection.models

        super

    update: ->
        @createButton.toggle @field.isMultiple() or @collection.hasSpots()

        this

    template: ->
        buttons = if @canCreate() then b_btn("", "plus", ["default", "create"]) else ""

        """
        <div class='header field-label'>
            #{ @helpTemplate() }#{ _.escape @field.getLabel() } #{ buttons }
        </div>
        <div class="error-container has-error">#{ @errorTemplate() }</div>
        <div class="body" id="#{ @componentId "body" }"></div>
        """

    canCreate: -> @isEditable and @field.getReference().createPermitted()

    dispose: ->
        view.remove() for cid, view of @views
        @views = {}
        @focusable = null

        this

    remove: ->
        @dispose()

        super

    isFocusable: ->
        return no if not super

        return (@field.isMultiple() and @canCreate()) or (not @field.isMultiple() and @focusable?)

    focus: ->
        if @field.isMultiple() then @createButton[0]?.focus() else @focusable?.focus()

        this

class Cruddy.Fields.EmbeddedItemView extends Cruddy.Layout.Layout
    className: "has-many-item-view"

    events:
        "click .btn-toggle": "toggleItem"

    constructor: (options) ->
        @collection = options.collection

        @listenTo @collection, "restore removeSoftly", (m) ->
            return if m isnt @model

            @$container.toggle not @model.isDeleted
            @$btn.html @buttonContents()

        super

    toggleItem: (e) ->
        if @model.isDeleted then @collection.restore @model else @collection.removeSoftly @model

        return false

    buttonContents: ->
        if @model.isDeleted
            Cruddy.lang.restore
        else
            b_icon("trash") + " " + Cruddy.lang.delete

    setupDefaultLayout: ->
        @append new FieldList {}, this

        return this

    render: ->
        @$el.html @template()

        @$container = @$component "body"
        @$btn = @$component "btn"

        super

    template: ->
        html = """<div id="#{ @componentId "body" }"></div>"""

        if not @disabled and (@model.entity.deletePermitted() or @model.isNew())
            html += """
                <button type="button" class="btn btn-default btn-sm btn-toggle" id="#{ @componentId "btn" }">
                    #{ @buttonContents() }
                </button>
            """

        return html

class Cruddy.Fields.RelatedCollection extends Backbone.Collection

    initialize: (items, options) ->
        @owner = options.owner
        @field = options.field
        @maxItems = options.maxItems

        # The flag is set when user has deleted some items
        @deleted = no
        @removedSoftly = 0

        @listenTo @owner, "sync", => @deleted = false

        super

    add: ->
        @removeSoftDeleted() if @maxItems and @models.length >= @maxItems

        super

    removeSoftDeleted: -> @remove @filter((m) -> m.isDeleted)

    remove: (m) ->
        @deleted = yes

        if _.isArray m
            @removedSoftly-- for item in m when item.isDeleted
        else
            @removedSoftly-- if m.isDeleted

        super

    removeSoftly: (m) ->
        return if m.isDeleted

        m.isDeleted = yes
        @removedSoftly++

        @trigger "removeSoftly", m

        return this

    restore: (m) ->
        return if not m.isDeleted

        m.isDeleted = no
        @removedSoftly--

        @trigger "restore", m

        return this

    hasSpots: (num = 1)-> not @maxItems? or @models.length - @removedSoftly + num <= @maxItems

    hasChangedSinceSync: ->
        return yes if @deleted or @removedSoftly
        return yes for item in @models when item.hasChangedSinceSync()

        no

    copy: (copy) ->
        items = if @field.isUnique() then [] else (item.copy() for item in @models)

        new Cruddy.Fields.RelatedCollection items,
            owner: copy
            field: @field

    serialize: ->
        if @field.isMultiple()
            models = @filter (m) -> not m.isDeleted

            return "" if _.isEmpty models

            data = {}

            data[item.cid] = item for item in models

            data
        else
            @find((m) -> not m.isDeleted) or ""

class Cruddy.Fields.Embedded extends Cruddy.Fields.BaseRelation

    viewConstructor: Cruddy.Fields.EmbeddedView

    createInstance: (model, items) ->
        return items if items instanceof Backbone.Collection

        items = (if items or @isRequired(model) then [ items ] else []) if not @attributes.multiple

        ref = @getReference()
        items = (ref.createInstance item for item in items)

        new Cruddy.Fields.RelatedCollection items,
            owner: model
            field: this
            maxItems: if @isMultiple() then null else 1

    applyValues: (collection, items) ->
        items = [ items ] if not @attributes.multiple

        collection.set _.pluck(items, "attributes"), add: no

        # Add new items
        ref = @getReference()

        collection.add (ref.createInstance item for item in items when not collection.get item.id)

        this

    hasChangedSinceSync: (items) -> items.hasChangedSinceSync()

    copy: (copy, items) -> items.copy(copy)

    processErrors: (collection, errorsCollection) ->
        return if not _.isObject errorsCollection

        if not @attributes.multiple
            model = collection.first()
            model.trigger "invalid", model, errorsCollection if model

            return this

        for cid, errors of errorsCollection
            model = collection.get cid
            model.trigger "invalid", model, errors if model

        this

    triggerRelated: (event, collection, args) ->
        model.trigger.apply model, [ event, model ].concat(args) for model in collection.models

        this

    isMultiple: -> @attributes.multiple

class Cruddy.Fields.Number extends Cruddy.Fields.Input

    createFilterInput: (model) -> new Cruddy.Inputs.NumberFilter
        model: model
        key: @id
class Cruddy.Fields.Computed extends Cruddy.Fields.Base
    createInput: (model) -> new Cruddy.Inputs.Static { model: model, key: @id, formatter: this }

    isEditable: -> false
Cruddy.Columns = new Factory

class Cruddy.Columns.Base extends Attribute
    initialize: (attributes) ->
        @formatter = Cruddy.formatters.create attributes.formatter, attributes.formatter_options if attributes.formatter?

        super

    render: (item) -> @format item[@id]

    # Return value's text representation
    format: (value) -> if @formatter? then @formatter.format value else _.escape value

    # Get column's header text
    getHeader: -> @attributes.header

    # Get column's class name
    getClass: -> "col-" + @id

    # Get whether a column can order items
    canOrder: -> @attributes.can_order
class Cruddy.Columns.Proxy extends Cruddy.Columns.Base
    initialize: (attributes) ->
        field = attributes.field ? attributes.id
        @field = attributes.entity.fields.get field

        @set "header", @field.get "label" if attributes.header is null

        super

    format: (value) -> if @formatter? then @formatter.format value else @field.format value

    getClass: -> super + " col-" + @field.get "type"
class Cruddy.Columns.Computed extends Cruddy.Columns.Base
    getClass: -> super + " col-computed"
class Cruddy.Columns.Actions extends Attribute

    getHeader: -> ""

    getClass: -> "col-actions"

    canOrder: -> false

    render: (item) -> """
        <div class="btn-group btn-group-xs">
            <a href="#{ Cruddy.baseUrl + "/" + @entity.link() + "?id=" + item.id }" data-action="edit" data-navigate="#{ item.id }" class="btn btn-default">
                #{ b_icon("pencil") }
            </a>
        </div>
    """

Cruddy.formatters = new Factory

class BaseFormatter
    defaultOptions: {}

    constructor: (options = {}) ->
        @options = $.extend {}, @defaultOptions, options

        this

    format: (value) -> value
class Cruddy.formatters.Image extends BaseFormatter
    defaultOptions:
        width: 40
        height: 40

    format: (value) ->
        return "" if _.isEmpty value
        value = value[0] if _.isArray value
        value = value.title if _.isObject value

        """
        <a href="#{ Cruddy.root + "/" + value }" data-trigger="fancybox">
            <img src="#{ thumb value, @options.width, @options.height }" #{ if @options.width then " width=#{ @options.width }" else "" } #{ if @options.height then " height=#{ @options.height }" else "" } alt="#{ _.escape value }">
        </a>
        """
class Cruddy.formatters.Plain extends BaseFormatter
    format: (value) -> _.escape value
Cruddy.Entity = {}

class Cruddy.Entity.Entity extends Backbone.Model

    initialize: (attributes, options) ->
        @fields = @createCollection Cruddy.Fields, attributes.fields
        @columns = @createCollection Cruddy.Columns, attributes.columns
        @permissions = Cruddy.permissions[@id]

        return this

    createCollection: (factory, items) ->
        data = []
        for options in items
            options.entity = this
            instance = factory.create options.class, options
            data.push instance if instance?

        new Backbone.Collection data

    # Create a datasource that will require specified columns and can be filtered
    # by specified filters
    createDataSource: (data) ->
        new DataSource data, { entity: this, filter: new Backbone.Model }

    # Create filters for specified columns
    createFilters: (columns = @columns) ->
        filters = (col.createFilter() for col in columns.models when col.get("filter_type") is "complex")

        new Backbone.Collection filters

    # Create an instance for this entity
    createInstance: (attributes = {}, options = {}) ->
        options.extra = attributes.extra
        options.entity = this
        
        attributes = _.extend {}, @get("defaults"), attributes.attributes

        new Cruddy.Entity.Instance attributes, options

    # Get relation field
    getRelation: (id) ->
        field = @field id

        if not field instanceof Cruddy.Fields.BaseRelation
            console.error "The field #{id} is not a relation."

            return

        field

    # Get a field with specified id
    field: (id) ->
        if not field = @fields.get id
            console.error "The field #{id} is not found."

            return

        return field

    search: (options = {}) -> new SearchDataSource {}, $.extend { url: @url() }, options

    # Load a model
    load: (id, success, fail) ->
        xhr = $.ajax
            url: @url(id)
            type: "GET"
            dataType: "json"
            cache: yes
            displayLoading: yes

        xhr = xhr.then (resp) =>
            resp = resp.data

            @createInstance resp

        xhr.done success if success
        xhr.fail fail if fail

        return xhr

    # Load a model and set it as current
    actionUpdate: (id) -> @load(id).then (instance) =>
            @set "instance", instance

            instance

    # Create new model and set it as current
    actionCreate: -> @set "instance", @createInstance()

    # Get only those attributes are not unique for the model
    getCopyableAttributes: (model, attributes) ->
        data = {}
        data[field.id] = attributes[field.id] for field in @fields.models when not field.isUnique() and field.id of attributes and not _.contains(@attributes.related, field.id)

        for ref in @attributes.related when ref of attributes
            data[ref] = @getRelation(ref).copy model, attributes[ref]

        data

    # Get url that handles syncing
    url: (id) -> entity_url @id, id

    # Get link to this entity or to the item of the entity
    link: (id) -> @id + if id? then "/" + id else ""

    # Get title in plural form
    getPluralTitle: -> @attributes.title.plural

    # Get title in singular form
    getSingularTitle: -> @attributes.title.singular

    getPermissions: -> @permissions

    updatePermitted: -> @permissions.update

    createPermitted: -> @permissions.create

    deletePermitted: -> @permissions.delete

    viewPermitted: -> @permissions.view

    isSoftDeleting: -> @attributes.soft_deleting
class Cruddy.Entity.Instance extends Backbone.Model
    constructor: (attributes, options) ->
        @entity = options.entity
        @related = {}

        super
        
    initialize: (attributes, options) ->
        @original = _.clone attributes
        @extra = options.extra ? {}

        @on "error", @processError, this
        @on "invalid", @processInvalid, this
        @on "sync", @handleSync, this
        @on "destroy", => @set "deleted_at", moment().unix() if @entity.get "soft_deleting"

        @on event, @triggerRelated(event), this for event in ["sync", "request"]

        this

    handleSync: (model, resp) ->
        @original = _.clone @attributes
        @extra = resp.data.extra

        this

    # Get a function handler that passes events to the related models
    triggerRelated: (event) -> 
        slice = Array.prototype.slice

        (model) ->
            for id, related of @related
                relation = @entity.getRelation id
                relation.triggerRelated.call relation, event, related, slice.call arguments, 1

            this

    processInvalid: (model, errors) ->
        # Trigger errors for related models
        @entity.getRelation(id).processErrors model, errors[id] for id, model of @related when id of errors

        this

    processError: (model, xhr) ->
        @trigger "invalid", this, xhr.responseJSON.data if xhr.responseJSON?.error is "VALIDATION"

        this

    validate: ->
        @set "errors", {}
        null

    link: -> @entity.link if @isNew() then "create" else @id

    url: -> @entity.url @id

    set: (key, val, options) ->
        if typeof key is "object"
            attrs = key
            options = val
            is_copy = options?.is_copy

            for id in @entity.get "related" when id of attrs
                relation = @entity.getRelation id
                relationAttrs = attrs[id]

                if is_copy
                    related = @related[id] = relationAttrs
                else
                    related = @related[id] = relation.createInstance this, relationAttrs

                # Attribute will now hold instance
                attrs[id] = related

        super

    sync: (method, model, options) ->
        if method in ["update", "create"]
            # Form data will allow us to upload files via AJAX request
            options.data = new AdvFormData(options.attrs ? @attributes).original

            # Set the content type to false to let browser handle it
            options.contentType = false
            options.processData = false

        super

    parse: (resp) -> resp.data.attributes

    copy: ->
        copy = @entity.createInstance()

        copy.set @getCopyableAttributes(copy),
            silent: yes
            is_copy: yes

        copy

    getCopyableAttributes: (copy) -> @entity.getCopyableAttributes copy, @attributes

    hasChangedSinceSync: ->
        return yes for key, value of @attributes when if key of @related then @entity.getRelation(key).hasChangedSinceSync value else not _.isEqual value, @original[key]

        no

    # Get whether is allowed to save instance
    isSaveable: -> (@isNew() and @entity.createPermitted()) or (not @isNew() and @entity.updatePermitted())

    serialize: -> { attributes: @attributes, id: @id }

    # Get current action on the model
    action: -> if @isNew() then "create" else "update"
class Cruddy.Entity.Page extends Cruddy.View
    className: "page entity-page"

    events: {
        "click .btn-create": "create"
        "click .btn-refresh": "refresh"
        "click [data-navigate]": "navigate"
    }

    constructor: (options) ->
        @className += " entity-page-" + options.model.id

        super

    initialize: (options) ->
        @dataSource = @model.createDataSource @getDatasourceData()
        
        @listenTo @dataSource, "change", (model) -> Cruddy.router.refreshQuery @getDatasourceDefaults(), model.attributes

        @listenTo Cruddy.router, "route:index", =>
            @dataSource.holdFetch().set(@getDatasourceData()).fetch()

            @_toggleForm()

        super

    getDatasourceDefaults: ->
        return @dsDefaults if @dsDefaults

        @dsDefaults = data =
            current_page: 1
            order_by: @model.get "order_by"
            order_dir: "asc"
            search: ""

        if data.order_by and (col = @model.columns.get(data.order_by))
            data.order_dir = col.get "order_dir"

        return data

    getDatasourceData: -> $.extend {}, @getDatasourceDefaults(), Cruddy.router.query.keys

    navigate: (e) ->
        @display $(e.currentTarget).data("navigate")

        return false

    display: (id) -> @_toggleForm(id).done =>

        id = id.id or "new" if id instanceof Cruddy.Entity.Instance

        if id then Cruddy.router.setQuery "id", id else Cruddy.router.removeQuery "id"

        return

    _toggleForm: (instanceId) ->
        instanceId = instanceId ? Cruddy.router.getQuery("id") or null

        if instanceId instanceof Cruddy.Entity.Instance
            instance = instanceId
            instanceId = instance.id or "new"

        dfd = $.Deferred()

        if @form
            compareId = if @form.model.isNew() then "new" else @form.model.id

            if instanceId is compareId or not @form.confirmClose()

                dfd.reject()

                return dfd.promise()

        if @form
            @form.remove()
            @form = null
            @model.set "instance", null

        resolve = (instance) =>
            @_displayForm instance
            dfd.resolve instance

        instance = @model.createInstance() if instanceId is "new" and not instance

        if instance
            resolve instance

            return dfd.promise()

        if instanceId
            @model.load(instanceId).done(resolve).fail -> dfd.reject()
        else
            dfd.resolve()

        return dfd.promise()

    _displayForm: (instance) ->
        @form = new Cruddy.Entity.Form model: instance
        @$el.append @form.render().$el

        @form.once "close", =>
            Cruddy.router.removeQuery "id"
            @_toggleForm()

        @listenTo instance, "sync", (model) -> Cruddy.router.setQuery "id", model.id
        @form.once "remove", => @stopListening instance

        after_break => @form.show()

        @model.set "instance", instance

        this

    create: ->
        @display "new"

        this

    refresh: (e) ->
        btn = $ e.currentTarget
        btn.prop "disabled", yes

        @dataSource.fetch().always -> btn.prop "disabled", no

        this

    render: ->
        @$el.html @template()
        
        @dataSource.fetch()

        # Search input
        @search = @createSearchInput @dataSource

        @$component("search").append @search.render().$el

        # Filters
        if not _.isEmpty filters = @dataSource.entity.get "filters"
            @filterList = @createFilterList @dataSource.filter, filters

            @$component("filters").append @filterList.render().el

        # Data grid
        @dataGrid = @createDataGrid @dataSource
        @pagination = @createPagination @dataSource
        
        @$component("body").append(@dataGrid.render().el).append(@pagination.render().el)

        @_toggleForm()

        this

    createDataGrid: (dataSource) -> new DataGrid
        model: dataSource
        entity: @model

    createPagination: (dataSource) -> new Pagination model: dataSource

    createFilterList: (model, filters) -> new FilterList
        model: model
        entity: @model
        filters: filters

    createSearchInput: (dataSource) -> new Cruddy.Inputs.Search
        model: dataSource
        key: "search"

    template: ->
        html = """
            <div class="content-header">
                <div class="column column-main">
                    <h1 class="entity-title">#{ @model.getPluralTitle() }</h1>

                    <div class="entity-title-buttons">
                        #{ @buttonsTemplate() }
                    </div>
                </div>

                <div class="column column-extra">
                    <div class="entity-search-box" id="#{ @componentId "search" }"></div>
                </div>
            </div>
            
            <div class="content-body">
                <div class="column column-main" id="#{ @componentId "body" }"></div>
                <div class="column column-extra" id="#{ @componentId "filters" }"></div>
            </div>
        """

    buttonsTemplate: ->
        html = """<button type="button" class="btn btn-default btn-refresh" title="#{ Cruddy.lang.refresh }">#{ b_icon "refresh" }</button>"""
        html += """ <button type="button" class="btn btn-primary btn-create" title="#{ Cruddy.lang.add }">#{ b_icon "plus" }</button>""" if @model.createPermitted()

        html

    remove: ->
        @form?.remove()
        @filterList?.remove()
        @dataGrid?.remove()
        @pagination?.remove()
        @search?.remove()
        @dataSource?.stopListening()

        super
# View that displays a form for an entity instance
class Cruddy.Entity.Form extends Cruddy.Layout.Layout
    className: "entity-form"

    events:
        "click .btn-save": "save"
        "click .btn-close": "close"
        "click .btn-destroy": "destroy"
        "click .btn-copy": "copy"
        "click .btn-refresh": "refresh"

    constructor: (options) ->
        @className += " " + @className + "-" + options.model.entity.id

        super

    initialize: (options) ->
        super

        @inner = options.inner ? no

        @listenTo @model, "destroy", @handleDestroy
        @listenTo @model, "invalid", @displayInvalid
        @listenTo @model, "change",  @handleChange

        @listenTo model, "change",  @handleChange for key, model of @model.related

        @hotkeys = $(document).on "keydown." + @cid, "body", $.proxy this, "hotkeys"

        $(window).on "beforeunload.#{ @cid }", => @confirmationMessage(yes)

        return this

    setupDefaultLayout: ->
        tab = @append new Cruddy.Layout.TabPane { title: @model.entity.get("title").singular }, this

        tab.append new Cruddy.Layout.Field { field: field.id }, tab for field in @entity.fields.models

        return this

    hotkeys: (e) ->
        # Ctrl + Z
        if e.ctrlKey and e.keyCode is 90 and e.target is document.body
            @model.set @model.previousAttributes()
            return false

        # Ctrl + Enter
        if e.ctrlKey and e.keyCode is 13
            @save()
            return false

        # Escape
        if e.keyCode is 27
            @close()
            return false

        this

    handleChange: -> 
        # @$el.toggleClass "dirty", @model.hasChangedSinceSync()

        this

    displayAlert: (message, type, timeout) ->
        @alert.remove() if @alert?

        @alert = new Alert
            message: message
            className: "flash"
            type: type
            timeout: timeout

        @footer.prepend @alert.render().el

        this

    displaySuccess: -> @displayAlert Cruddy.lang.success, "success", 3000

    displayInvalid: -> @displayAlert Cruddy.lang.invalid, "warning", 5000

    displayError: (xhr) -> @displayAlert Cruddy.lang.failure, "danger", 5000 unless xhr.responseJSON?.error is "VALIDATION"

    handleDestroy: ->
        if @model.entity.get "soft_deleting"
            @update()
        else
            if @inner then @remove() else Cruddy.router.navigate @model.entity.link(), trigger: true

        this

    show: ->
        @$el.toggleClass "opened", true

        @items[0].activate()

        @focus()

        this

    refresh: ->
        @model.fetch() if @confirmClose()

        return this

    save: ->
        return if @request?

        @request = @model.save null,
            displayLoading: yes

            xhr: =>
                xhr = $.ajaxSettings.xhr()
                xhr.upload.addEventListener('progress', $.proxy @, "progressCallback") if xhr.upload

                xhr

        @request.done($.proxy this, "displaySuccess").fail($.proxy this, "displayError")

        @request.always =>
            @request = null
            @progressBar.parent().hide()
            @update()

        @update()

        this

    progressCallback: (e) ->
        if e.lengthComputable
            width = (e.loaded * 100) / e.total

            @progressBar.width(width + '%').parent().show()

        this

    close: ->
        if @confirmClose()
            @remove()
            @trigger "close"

        this

    confirmClose: -> not (message = @confirmationMessage()) or confirm message

    confirmationMessage: (closing) ->
        return (if closing then Cruddy.lang.onclose_abort else Cruddy.lang.confirm_abort) if @request

        return (if closing then Cruddy.lang.onclose_discard else Cruddy.lang.confirm_discard) if @model.hasChangedSinceSync()

    destroy: ->
        return if @request or @model.isNew()

        softDeleting = @model.entity.get "soft_deleting"

        confirmed = if not softDeleting then confirm(Cruddy.lang.confirm_delete) else yes

        if confirmed
            @request = if @softDeleting and @model.get "deleted_at" then @model.restore else @model.destroy wait: true

            @request.always => @request = null

        this

    copy: ->
        Cruddy.app.page.display @model.copy()

        this

    render: ->
        @$el.html @template()

        @$container = @$component "body"

        @nav = @$component "nav"
        @footer = @$ "footer"
        @submit = @$ ".btn-save"
        @destroy = @$ ".btn-destroy"
        @copy = @$ ".btn-copy"
        @$refresh = @$ ".btn-refresh"
        @progressBar = @$ ".form-save-progress"

        @update()

        super

    renderElement: (el) ->
        @nav.append el.getHeader().render().$el

        super

    update: ->
        permit = @model.entity.getPermissions()
        isNew = @model.isNew()

        @$el.toggleClass "loading", @request?

        @submit.text if isNew then Cruddy.lang.create else Cruddy.lang.save
        @submit.attr "disabled", @request?
        @submit.toggle if isNew then permit.create else permit.update

        @destroy.attr "disabled", @request?
        @destroy.toggle not isNew and permit.delete
        
        @copy.toggle not isNew and permit.create
        @$refresh.toggle not isNew

        @external?.remove()

        @destroy.before @external = $ @externalTemplate @model.extra.external if @model.extra.external

        this

    template: ->
        """
        <div class="navbar navbar-default navbar-static-top" role="navigation">
            <div class="container-fluid">
                <ul id="#{ @componentId "nav" }" class="nav navbar-nav"></ul>
            </div>
        </div>

        <div class="tab-content" id="#{ @componentId "body" }"></div>

        <footer>
            <div class="pull-left">
                <button type="button" class="btn btn-link btn-destroy" title="#{ Cruddy.lang.model_delete }">
                    <span class="glyphicon glyphicon-trash"></span>
                </button>
                
                <button type="button" tabindex="-1" class="btn btn-link btn-copy" title="#{ Cruddy.lang.model_copy }">
                    <span class="glyphicon glyphicon-book"></span>
                </button>
                
                <button type="button" class="btn btn-link btn-refresh" title="#{ Cruddy.lang.model_refresh }">
                    <span class="glyphicon glyphicon-refresh"></span>
                </button>
            </div>

            <button type="button" class="btn btn-default btn-close">#{ Cruddy.lang.close }</button>
            <button type="button" class="btn btn-primary btn-save"></button>

            <div class="progress"><div class="progress-bar form-save-progress"></div></div>
        </footer>
        """

    externalTemplate: (href) ->"""
        <a href="#{ href }" class="btn btn-link navbar-btn pull-right" title="#{ Cruddy.lang.view_external }" target="_blank">
            #{ b_icon "eye-open" }
        </a>
        """

    remove: ->
        @trigger "remove", @
        
        @request.abort() if @request
        
        @$el.one(TRANSITIONEND, =>
            $(document).off "." + @cid
            $(window).off "." + @cid

            @trigger "removed", @

            super
        )
        .removeClass "opened"

        super
# Backend application file

class App extends Backbone.Model

    initialize: ->
        @container = $ "body"
        @mainContent = $ "#content"
        @loadingRequests = 0
        @entities = {}
        @dfd = $.Deferred()

        @on "change:entity", @displayEntity, this

        this

    init: ->
        @loadSchema()

        return this

    ready: (callback) -> @dfd.done callback

    loadSchema: ->
        req = $.ajax
            url: entity_url "_schema"
            displayLoading: yes

        req.done (resp) =>
            @entities[entity.id] = new Cruddy.Entity.Entity entity for entity in resp.data

            @dfd.resolve this

            return

        req.fail =>
            @dfd.reject()

            @displayError Cruddy.lang.schema_failed

            return

        return req

    displayEntity: (model, entity) ->
        @dispose()

        @mainContent.hide()
        @container.append (@page = new Cruddy.Entity.Page model: entity).render().el if entity

    displayError: (error) ->
        @dispose()
        @mainContent.html("<p class='alert alert-danger'>#{ error }</p>").show()

        this

    startLoading: ->
        @loading = setTimeout (=>
            $(document.body).addClass "loading"
            @loading = no

        ), 1000 if @loadingRequests++ is 0

        this

    doneLoading: ->
        if @loadingRequests is 0
            console.error "Seems like doneLoading is called too many times."

            return

        if --@loadingRequests is 0
            if @loading
                clearTimeout @loading
                @loading = no
            else
                $(document.body).removeClass "loading"

        this

    entity: (id) ->
        console.error "Unknown entity #{ id }" if not id of @entities

        @entities[id]

    dispose: ->
        @page?.remove()

        this

class Router extends Backbone.Router

    initialize: ->
        @query = $.query

        entities = Cruddy.entities

        @addRoute "index", entities
        #@addRoute "update", entities, "([^/]+)"
        #@addRoute "create", entities, "create"

        root = Cruddy.root + "/" + Cruddy.uri + "/"
        history = Backbone.history

        $(document.body).on "click", "a", (e) =>
            fragment = e.currentTarget.href
            
            return if fragment.indexOf(root) isnt 0

            fragment = history.getFragment fragment.slice root.length

            # Try to find a handler for the fragment and if it is found, navigate
            # to it and cancel the default event
            for handler in history.handlers when handler.route.test(fragment)
                e.preventDefault()
                history.navigate fragment, trigger: yes

                break

            return

        this

    execute: ->
        @query = $.query.parseNew location.search

        super

    navigate: (fragment) ->
        @query = @query.load fragment

        super

    getQuery: (key) -> @query.GET key

    setQuery: (key, value) -> @updateQuery @query.set key, value

    refreshQuery: (defaults, actual) ->
        q = @query.copy()

        for key, val of defaults
            if (value = actual[key]) isnt val
                q.SET key, value
            else
                q.REMOVE key

        @updateQuery q

    removeQuery: (key) -> @updateQuery @query.remove key

    updateQuery: (query) ->
        if (qs = query.toString()) isnt @query.toString()
            @query = query

            path = location.pathname
            uri = "/" + Cruddy.uri + "/"
            path = path.slice uri.length if path.indexOf(uri) is 0

            Backbone.history.navigate path + qs

        return this

    createApp: ->
        if not Cruddy.app
            Cruddy.app = new App
            Cruddy.app.init()

        return Cruddy.app

    addRoute: (name, entities, appendage = null) ->
        route = "^(#{ entities })"
        route += "/" + appendage if appendage
        route += "(\\?.*)?$"

        @route new RegExp(route), name

        this

    resolveEntity: (id, callback) -> @createApp().ready (app) ->
        entity = app.entity(id)

        if entity.viewPermitted()
            entity.set "instance", null
            Cruddy.app.set "entity", entity

            callback.call this, entity if callback
        else
            Cruddy.app.displayError Cruddy.lang.entity_forbidden

        return

    index: (entity) -> @resolveEntity entity

    #create: (entity) -> @resolveEntity entity, (entity) -> entity.actionCreate()

    #update: (entity, id) -> @resolveEntity entity, (entity) -> entity.actionUpdate id

$ ->
    Cruddy.router = new Router
    
    Backbone.history.start
        root: Cruddy.uri
        pushState: true
        hashChange: false