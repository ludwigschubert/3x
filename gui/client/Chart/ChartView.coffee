# Define just a necessary construct for all CoffeeScript files, with code between (\ ... ) ?
define (require) -> (\

$ = require "jquery"
_ = require "underscore"
d3 = require "d3"
require "jsrender"

_3X_ = require "3x"
{
    log
    error
} =
utils = require "utils"

CompositeElement = require "CompositeElement"

class ResultsChart extends CompositeElement
    constructor: (@baseElement, @typeSelection, @axesControl, @table, @optionElements = {}) ->
        super @baseElement

        @axisNames = try JSON.parse localStorage["chartAxes"]
        @axesControl
            .on("click", ".axis-add    .axis-var", @actionHandlerForAxisControl @handleAxisAddition)
            .on("click", ".axis-change .axis-var", @actionHandlerForAxisControl @handleAxisChange)
            .on("click", ".axis-change .axis-remove", @actionHandlerForAxisControl @handleAxisRemoval)

        @table.on "changed", @initializeAxes
        @table.on "updated", @display

        $(window).resize(_.throttle @display, 100)

        # hide all popover when not clicked on one
        $('html').on("click", (e) =>
            if $(e.target).closest(".dot, .popover").length == 0
                @baseElement.find(".dot").popover("hide")
        )
        # enable nested popover on-demand
        @baseElement.on("click", ".popover [data-toggle='popover']", (e) =>
            $(e.target).closest("[data-toggle='popover']").popover("show")
        )

        # vocabularies for option persistence
        @chartOptions = (try JSON.parse localStorage["chartOptions"]) ? {}
        persistOptions = => localStorage["chartOptions"] = JSON.stringify @chartOptions
        optionToggleHandler = (e) =>
            btn = $(e.target).closest(".btn")
            return e.preventDefault() if btn.hasClass("disabled")
            chartOption = btn.attr("data-toggle-option")
            @chartOptions[chartOption] = not btn.hasClass("active")
            do persistOptions
            do @display
        # vocabs for installing toggle handler to buttons
        installToggleHandler = (chartOption, btn) =>
            return btn
               ?.toggleClass("active", @chartOptions[chartOption] ? false)
                .attr("data-toggle-option", chartOption)
                .click(optionToggleHandler)
        # vocabularies for axis options
        forEachAxisOptionElement = (prefix, chartOptionPrefix, job) =>
            for axisName in ResultsChart.AXIS_NAMES
                optionKey = chartOptionPrefix+axisName
                job optionKey, @optionElements["#{prefix}#{axisName}"], axisName

        installToggleHandler "interpolateLines", @optionElements.toggleInterpolateLines
        installToggleHandler "hideLines",        @optionElements.toggleHideLines
        # log scale
        @optionElements.toggleLogScale =
            $(forEachAxisOptionElement "toggleLogScale", "logScale", installToggleHandler)
                .toggleClass("disabled", true)
        # origin
        @optionElements.toggleOrigin =
            $(forEachAxisOptionElement "toggleOrigin", "origin", installToggleHandler)
                .toggleClass("disabled", true)

    @AXIS_NAMES: "X Y1 Y2".trim().split(/\s+/)

    persist: =>
        localStorage["chartAxes"] = JSON.stringify @axisNames

    @AXIS_PICK_CONTROL_SKELETON: $("""
        <script type="text/x-jsrender">
          <div data-order="{{>ord}}" class="axis-control axis-change btn-group">
            <a class="btn btn-small dropdown-toggle" data-toggle="dropdown"
              href="#"><span class="axis-name">{{>axis.name}}</span>
                  <span class="caret"></span></a>
            <ul class="dropdown-menu" role="menu" aria-labelledby="dLabel">
              {{for variables}}
                <li class="axis-var" data-name="{{>name}}"><a href="#"><i
                    class="icon icon-{{if isMeasured}}dashboard{{else}}tasks{{/if}}"></i>
                        {{>name}}</a></li>
              {{/for}}
              {{if isOptional}}
                {{if variables.length > 0}}<li class="divider"></li>{{/if}}
                <li class="axis-remove"><a href="#"><i class="icon icon-remove"></i> Remove</a></li>
              {{/if}}
            </ul>
          </div>
        </script>
        """)
    @AXIS_ADD_CONTROL_SKELETON: $("""
        <script type="text/x-jsrender">
          <div class="axis-control axis-add btn-group">
            <a class="btn btn-small dropdown-toggle" data-toggle="dropdown"
              href="#">… <span class="caret"></span></a>
            <ul class="dropdown-menu" role="menu" aria-labelledby="dLabel">
              {{for variables}}
                <li class="axis-var" data-name="{{>name}}"><a href="#"><i
                    class="icon icon-{{if isMeasured}}dashboard{{else}}tasks{{/if}}"></i>
                    {{>name}}</a></li>
              {{/for}}
            </ul>
          </div>
        </script>
        """)

    actionHandlerForAxisControl: (action) => (e) =>
        e.preventDefault()
        $this = $(e.target)
        $axisControl = $this.closest(".axis-control")
        ord = +$axisControl.attr("data-order")
        name = $this.closest(".axis-var").attr("data-name")
        action ord, name, $axisControl, $this, e
    handleAxisChange: (ord, name, $axisControl) =>
        $axisControl.find(".axis-name").text(name)
        @axisNames[ord] = name
        # TODO proceed only when something actually changes
        do @persist
        do @initializeAxes
    handleAxisAddition: (ord, name, $axisControl) =>
        @axisNames.push name
        do @persist
        do @initializeAxes
    handleAxisRemoval: (ord, name, $axisControl) =>
        @axisNames.splice ord, 1
        do @persist
        do @initializeAxes

    @X_AXIS_ORDINAL: 1 # second variable is X
    @Y_AXIS_ORDINAL: 0 # first variable is Y
    initializeAxes: => # initialize @axes from @axisNames
        if @table.deferredDisplay?
            do @table.render # XXX charting heavily depends on the rendered table, so force rendering
        return unless @table.columnsRendered?.length
        # collect candidate variables for chart axes from ResultsTable
        axisCandidates =
            # only the expanded input variables or output variables can be charted
            (col for col in @table.columnsRendered when col.isExpanded or col.isMeasured)
        nominalVariables =
            (axisCand for axisCand in axisCandidates when utils.isNominal axisCand.type)
        ratioVariables =
            (axisCand for axisCand in axisCandidates when utils.isRatio axisCand.type)
        # check if there are enough variables to construct a two-dimensional chart
        canDrawChart = (possible) =>
            @baseElement.add(@optionElements.chartOptions).toggleClass("hide", not possible)
            @optionElements.alertChartImpossible?.toggleClass("hide", possible)
        if ratioVariables.length >= 1 and nominalVariables.length + ratioVariables.length >= 2
            canDrawChart yes
        else
            canDrawChart no
            return
        # validate the variables chosen for axes
        defaultAxes = []
        defaultAxes[ResultsChart.X_AXIS_ORDINAL] = nominalVariables[0]?.name ? ratioVariables[1]?.name
        defaultAxes[ResultsChart.Y_AXIS_ORDINAL] = ratioVariables[0]?.name
        if @axisNames?
            # find if all axisNames are valid, don't appear more than once, or make them default
            for name,ord in @axisNames when (@axisNames.indexOf(name) isnt ord or
                    not axisCandidates.some (col) => col.name is name)
                @axisNames[ord] = defaultAxes[ord] ? null
            # discard any null/undefined elements
            @axisNames = @axisNames.filter (name) => name?
        else
            # default axes
            @axisNames = defaultAxes
        # collect ResultsTable columns that corresponds to the @axisNames
        @vars = @axisNames.map (name) => @table.columns[name]
        @varX      = @vars[ResultsChart.X_AXIS_ORDINAL]
        @varsPivot = (ax for ax,ord in @vars when ord isnt ResultsChart.X_AXIS_ORDINAL and utils.isNominal ax.type)
        @varsY     = (ax for ax,ord in @vars when ord isnt ResultsChart.X_AXIS_ORDINAL and utils.isRatio   ax.type)
        # clear title
        @optionElements.chartTitle?.text("")
        # check if there are more than two units for Y-axis, and discard any variables that violates it
        @varsYbyUnit = _.groupBy @varsY, (col) => col.unit
        if (_.size @varsYbyUnit) > 2
            @varsYbyUnit = {}
            for ax,ord in @varsY
                u = ax.unit
                (@varsYbyUnit[u] ?= []).push ax
                # remove Y axis variable if it uses a third unit
                if (_.size @varsYbyUnit) > 2
                    delete @varsYbyUnit[u]
                    @varsY[ord] = null
                    ord2 = @vars.indexOf ax
                    @vars.splice ord2, 1
                    @axisNames.splice ord2, 1
            @varsY = @varsY.filter (v) => v?
        # TODO validation of each axis type with the chart type
        # find out remaining variables
        remainingVariables = (
                if @axisNames.length < 3 or (_.size @varsYbyUnit) < 2
                    axisCandidates
                else # filter variables in a third unit when there're already two axes
                    ax for ax in axisCandidates when @varsYbyUnit[ax.unit]? or utils.isNominal ax.type
            ).filter((col) => col.name not in @axisNames)
        # render the controls
        @axesControl
            .find(".axis-control").remove().end()
            .append(
                for ax,ord in @vars
                    ResultsChart.AXIS_PICK_CONTROL_SKELETON.render({
                        ord: ord
                        axis: ax
                        variables: (if ord == ResultsChart.Y_AXIS_ORDINAL then ratioVariables else axisCandidates)
                                    # the first axis (Y) must always be of ratio type
                            .filter((col) => col not in @vars[0..ord]) # and without the current one
                        isOptional: (ord > 1) # there always has to be at least two axes
                    })
            )
        @axesControl.append(ResultsChart.AXIS_ADD_CONTROL_SKELETON.render(
            variables: remainingVariables
        )) if remainingVariables.length > 0

        do @display

    @SVG_STYLE_SHEET: """
        <style>
          .axis path,
          .axis line {
            fill: none;
            stroke: #000;
            shape-rendering: crispEdges;
          }

          .dot {
            opacity: 0.75;
            cursor: pointer;
          }

          .line {
            fill: none;
            stroke-width: 1.5px;
          }
        </style>
        """
    render: =>
        ## Collect data to plot from @table
        $trs = @table.baseElement.find("tbody tr")
        entireRowIndexes = $trs.map((i, tr) -> +tr.dataset.ordinal).get()
        resultsForRendering = @table.resultsForRendering
        return unless resultsForRendering?.length > 0
        accessorFor = (v) -> (rowIdx) -> resultsForRendering[rowIdx][v.index].value
        originFor   = (v) -> (rowIdx) -> resultsForRendering[rowIdx][v.index].origin
        @dataBySeries = _.groupBy entireRowIndexes, (rowIdx) =>
            @varsPivot.map((pvVar) -> accessorFor(pvVar)(rowIdx)).join(", ")
        # See: https://github.com/mbostock/d3/wiki/Ordinal-Scales#wiki-category10
        #TODO @decideColors
        color = d3.scale.category10()

        # f= null
        # f(1)

        intervalContains = (lu, xs...) ->
            (JSON.stringify d3.extent(lu)) is (JSON.stringify d3.extent(lu.concat(xs)))


        axisType = (ty) -> if utils.isNominal ty then "nominal" else if utils.isRatio ty then "ratio"
        formatAxisLabel = (axis) ->
            unit = axis.unit
            unitStr = if unit then "(#{unit})" else ""
            if axis.columns?.length == 1
                "#{axis.columns[0].name}#{if unitStr then " " else ""}#{unitStr}"
            else
                unitStr
        formatDataPoint = (varY) =>
            vars = [varY, @varX]
            varsImplied = vars.concat @varsPivot
            vars = vars.concat (
                col for col in @table.columnsRendered when \
                    col.isExpanded and col not in varsImplied
            )
            varsWithValueGetter = ([v, accessorFor(v)] for v in vars)
            getDataPointOrigin = originFor(varY)
            runColIdx = @table.results.names.indexOf _3X_.RUN_COLUMN_NAME
            yIdx = varY.dataIndex
            getRawData = (origin) =>
                rows = @table.results.rows
                for i in origin
                    [rows[i][yIdx], rows[i][runColIdx]]
            (d) ->
                origin = getDataPointOrigin(d)
                return "" unless origin?
                """<table class="table table-condensed">""" + [
                    (for [v,getValue] in varsWithValueGetter
                        val = getValue(d)
                        {
                            name: v.name
                            value: """<span class="value" title="#{val}">#{val}</span>#{
                                unless v.unit then ""
                                else "<small class='unit'> (#{v.unit})<small>"}"""
                        }
                    )...
                    {
                        name: "run#.count"
                        value: """<span class="run-details"
                            data-toggle="popover" data-html="true"
                            title="#{origin?.length} runs" data-content="
                            <small><ol class='chart-run-details'>#{
                                getRawData(origin).map(([yValue,runId]) ->
                                    "<li><a href='#{runId}/overview'
                                        target='run-details' title='#{runId}'>#{
                                        # show value of varY for this particular run
                                        yValue
                                    }</a></li>"
                                ).join("")
                            }</ol></small>"><span class="value">#{origin.length
                                }</span><small class="unit"> (runs)</small></span>"""
                    }
                    # TODO links to runIds
                ].map((row) -> "<tr><td>#{row.name}</td><th>#{row.value}</th></tr>")
                 .join("") + """</table>"""
        pickScale = (axis) =>
            dom = d3.extent(axis.domain)
            dom = d3.extent(dom.concat([0])) if @chartOptions["origin#{axis.name}"]
            if dom[0] == dom[1] or Math.abs (dom[0] - dom[1]) == Number.MIN_VALUE
                dom[0] -= 1
                dom[1] += 1
            axis.isLogScalePossible = not intervalContains dom, 0
            axis.isLogScaleEnabled = @chartOptions["logScale#{axis.name}"]
            if axis.isLogScaleEnabled and not axis.isLogScalePossible
                error "log scale does not work for domains including zero", axis, dom
                axis.isLogScaleEnabled = no
            (
                if axis.isLogScaleEnabled then d3.scale.log()
                else d3.scale.linear()
            ).domain(dom)

        do => ## Setup Axes
            @axes = []
            # X axis
            @axes.push
                name: "X"
                type: axisType @varX.type # space?
                unit: @varX.unit
                columns: [@varX]
                accessor: accessorFor(@varX)
            # Y axes: analyze the extent of Y axes data (single or dual unit)
            for vY in @varsY
                continue if @axes.length > 1 and vY.unit is @axes[1].unit
                i = @axes.length
                @axes.push axisY =
                    name: "Y#{i}"
                    type: axisType vY.type
                    unit: vY.unit
                    columns: @varsYbyUnit[vY.unit]
                # figure out the extent for this axis
                extent = []
                for col in axisY.columns
                    extent = d3.extent(extent.concat(d3.extent(entireRowIndexes, accessorFor(col))))
                axisY.domain = extent
        do => ## Determine the chart dimension and initialize the SVG root as @svg
            chartBody = d3.select(@baseElement[0])
            @baseElement.find("style").remove().end().append(ResultsChart.SVG_STYLE_SHEET)
            chartWidth  = window.innerWidth  - @baseElement.position().left * 2
            chartHeight = window.innerHeight - @baseElement.position().top - 20
            @baseElement.css
                width:  "#{chartWidth }px"
                height: "#{chartHeight}px"
            @margin =
                top: 20, bottom: 50
                right: 40, left: 40
            # adjust margins while we prepare the Y scales
            for axisY,i in @axes[1..]
                y = axisY.scale = pickScale(axisY).nice()
                axisY.axis = d3.svg.axis()
                    .scale(axisY.scale)
                numDigits = Math.max _.pluck(y.ticks(axisY.axis.ticks()).map(y.tickFormat()), "length")...
                tickWidth = Math.ceil(numDigits * 6.5) #px per digit
                if i == 0
                    @margin.left += tickWidth
                else
                    @margin.right += tickWidth
            @width  = chartWidth  - @margin.left - @margin.right
            @height = chartHeight - @margin.top  - @margin.bottom
            chartBody.select("svg").remove()
            @svg = chartBody.append("svg")
                .attr("width",  chartWidth)
                .attr("height", chartHeight)
              .append("g")
                .attr("transform", "translate(#{@margin.left},#{@margin.top})")
        do => ## Setup and draw X axis
            axisX = @axes[0]
            axisX.domain = entireRowIndexes.map(axisX.accessor)
            # based on the X axis type, decide its scale
            switch axisX.type
                when "nominal"
                    x = axisX.scale = d3.scale.ordinal()
                        .domain(axisX.domain)
                        .rangeRoundBands([0, @width], .1)
                    xData = axisX.accessor
                    axisX.coord = (d) -> x(xData(d)) + x.rangeBand()/2
                    @chartType = "lineChart"
                when "ratio"
                    x = axisX.scale = pickScale(axisX).nice()
                        .range([0, @width])
                    xData = axisX.accessor
                    axisX.coord = (d) -> x(xData(d))
                    @chartType = "scatterPlot"
                else
                    error "Unsupported variable type (#{axis.type}) for X axis", axisX.column
            axisX.label = formatAxisLabel axisX
            axisX.axis = d3.svg.axis()
                .scale(axisX.scale)
                .orient("bottom")
            @svg.append("g")
                .attr("class", "x axis")
                .attr("transform", "translate(0,#{@height})")
                .call(axisX.axis)
              .append("text")
                .attr("x", @width/2)
                .attr("dy", "3em")
                .style("text-anchor", "middle")
                .text(axisX.label)
        do => ## Setup and draw Y axis
            @axisByUnit = {}
            for axisY,i in @axes[1..]
                y = axisY.scale
                    .range([@height, 0])
                axisY.label = formatAxisLabel axisY
                # set up title
                @optionElements.chartTitle?.html(
                    # TODO move this code to a model class, e.g., ResultsQuery
                    """
                    <strong>#{@varsY[0]?.name}</strong>
                    by <strong>#{@varX.name}</strong> #{
                        if @varsPivot.length > 0
                            "for each #{
                                ("<strong>#{name}</strong>" for {name} in @varsPivot
                                ).join ", "}"
                        else ""
                    } #{
                        # XXX remove these hacks into ResultsSection, InputsView, OutputsView
                        {inputs,outputs} = _3X_.ResultsSection
                        filters = (
                            for name,values of inputs.menuItemsSelected when values?.length > 0
                                "<strong>#{name}=#{values.join(",")}</strong>"
                        ).concat(
                            for name,filter of outputs.menuFilter when filter?
                                "<strong>#{name}#{outputs.constructor.serializeFilter filter}</strong>"
                        )
                        if filters.length > 0
                            "<br>(#{filters.join(" and ")})"
                        else ""
                    }
                    """
                )
                # draw axis
                orientation = if i == 0 then "left" else "right"
                axisY.axis.orient(orientation)
                @svg.append("g")
                    .attr("class", "y axis")
                    .attr("transform", if orientation isnt "left" then "translate(#{@width},0)")
                    .call(axisY.axis)
                  .append("text")
                    .attr("transform", "translate(#{
                            if orientation is "left" then -@margin.left else @margin.right
                        },#{@height/2}), rotate(-90)")
                    .attr("dy", if orientation is "left" then "1em" else "-.3em")
                    .style("text-anchor", "middle")
                    .text(axisY.label)
                @axisByUnit[axisY.unit] = axisY

        ## Finally, draw each varY and series
        series = 0
        axisX = @axes[0]
        xCoord = axisX.coord
        for yVar in @varsY
            axisY = @axisByUnit[yVar.unit]
            y = axisY.scale; yData = accessorFor(yVar)
            yCoord = (d) -> y(yData(d))

            for seriesLabel,dataForCharting of @dataBySeries
                seriesColor = (d) -> color(series)

                @svg.selectAll(".dot.series-#{series}")
                    .data(dataForCharting)
                  .enter().append("circle")
                    .attr("class", "dot series-#{series}")
                    .attr("r", 5)
                    .attr("cx", xCoord)
                    .attr("cy", yCoord)
                    .style("fill", seriesColor)
                    # popover
                    .attr("title",        seriesLabel)
                    .attr("data-content", formatDataPoint yVar)
                    .attr("data-placement", (d) =>
                        if xCoord(d) < @width/2 then "right" else "left"
                    )

                switch @chartType
                    when "lineChart"
                        unless @chartOptions.hideLines
                            line = d3.svg.line().x(xCoord).y(yCoord)
                            line.interpolate("basis") if @chartOptions.interpolateLines
                            @svg.append("path")
                                .datum(dataForCharting)
                                .attr("class", "line")
                                .attr("d", line)
                                .style("stroke", seriesColor)

                if _.size(@varsY) > 1
                    if seriesLabel
                        seriesLabel = "#{seriesLabel} (#{yVar.name})"
                    else
                        seriesLabel = yVar.name
                else
                    unless seriesLabel
                        seriesLabel = yVar.name
                if _.size(@varsY) == 1 and _.size(@dataBySeries) == 1
                    seriesLabel = null

                # legend
                if seriesLabel?
                    i = dataForCharting.length - 1
                    #i = Math.round(Math.random() * i) # TODO find a better way to place labels
                    d = dataForCharting[i]
                    x = xCoord(d)
                    leftHandSide = x < @width/2
                    inTheMiddle = false # @width/4 < x < @width*3/4
                    @svg.append("text")
                        .datum(d)
                        .attr("transform", "translate(#{xCoord(d)},#{yCoord(d)})")
                        .attr("x", if leftHandSide then 5 else -5).attr("dy", "-.5em")
                        .style("text-anchor", if inTheMiddle then "middle" else if leftHandSide then "start" else "end")
                        .style("fill", seriesColor)
                        .text(seriesLabel)

                series++

        # popover
        @baseElement.find(".dot").popover(
            trigger: "click"
            html: true
            container: @baseElement
        )

        ## update optional UI elements
        @optionElements.toggleLogScale.toggleClass("disabled", true)
        for axis in @axes
            @optionElements["toggleLogScale#{axis.name}"]
               ?.toggleClass("disabled", not axis.isLogScalePossible)

        @optionElements.toggleOrigin.toggleClass("disabled", true)
        for axis in @axes
            @optionElements["toggleOrigin#{axis.name}"]
               ?.toggleClass("disabled", axis.type isnt "ratio" or intervalContains axis.domain, 0)

        isLineChartDisabled = @chartType isnt "lineChart"
        $(@optionElements.toggleHideLines)
           ?.toggleClass("disabled", isLineChartDisabled)
            .toggleClass("hide", isLineChartDisabled)
        $(@optionElements.toggleInterpolateLines)
           ?.toggleClass("disabled", isLineChartDisabled or @chartOptions.hideLines)
            .toggleClass("hide", isLineChartDisabled or @chartOptions.hideLines)


)
