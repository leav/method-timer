#==============================================================================
# ■ Method_Timer
#------------------------------------------------------------------------------
# 　监测方法调用时间模块
#   2008/8/4 1.0
#   因为set_trace_func造成的严重延迟，暂时不能用于游戏的测试…
#   2008/8/5 1.1
#   增加了用插入代码的办法来监测速度
#   2008/8/6 1.2
#   改变了定义方法的途径，现在可以重定义带super的方法了
#==============================================================================
=begin
使用方法：

监测：

1、执行Method_Timer.run_trace_func
此方法几乎适用于任何情况，但是会造成程序严重拖慢，不建议在游戏测试中使用。比较
适合算法片段的测试。

2、执行Method_Timer.hook(module)
module: 要检测的模块或类，Module
与方法1冲突。将一个类的所有实例方法重定义，加入监测代码。此方法运行起来比方法1
快很多，但不能监测单例方法、静态方法等。最好不要hook Ruby内建的类，重定义某些
方法可能会造成SystemStackError。由于重定义了所有实例方法，可能会造成未知的BUG。
可以配合Pudge模块获取已定义的模块。

3、定义一个方法的时候，在方法开始时加入Method_Timer.trace_call(file, line, id, classname)
结束的时候加入Method_Timer.trace_return(file, line, id, classname)
此方法几乎也适用于任何情况，只是工作量有时会比较大。可以用来弥补方法2的不足。
file: 文件名，String，可以设为 ""
line: 行数，Integer，可以设为 0 
id: 方法名，String或Symbol
classname: 方法所在的模块或类，Module

输出：

执行Method_Timer.log_by_time输出数据到MethodTimerResult.txt文件，按调用时间排序

执行Method_Timer.log_by_class也是输出数据，按类排序
=end

module Method_Timer
  #--------------------------------------------------------------------------
  # ● 常量
  #--------------------------------------------------------------------------
  LOG_FILE = 'MethodTimerResult.txt'
  HOOKED_METHOD_PREFIX = "module_timer_hooked_"
  module_function
  #--------------------------------------------------------------------------
  # ● 初始化
  #--------------------------------------------------------------------------
  def ini
    # 数据保存hash
    # key:[id, classname] value:Method_Trace实例
    @method_traces = {}
    # 保存已经重定义的方法
    @hooked_modules = [Method_Timer, Method_Trace]
  end
  #--------------------------------------------------------------------------
  # ● 用set_trace_func来监测所有的方法（此方法会造成程序严重拖慢）
  #--------------------------------------------------------------------------
  def run_trace_func
    set_trace_func proc {|event, file, line, id, binding, classname|
      if event.to_sym == :call        
        trace_call(file, line, id, classname)
      elsif event.to_sym == :return
        trace_return(file, line, id, classname)
      end
    }
  end
  #--------------------------------------------------------------------------
  # ● 停止运行set_trace_func
  #--------------------------------------------------------------------------
  def stop_trace_func
    set_trace_func(nil)
  end
  #--------------------------------------------------------------------------
  # ● 用插入代码的办法监测一个模块或类的所有实例方法
  #--------------------------------------------------------------------------
  def hook(a_module, hook_super = false)
    # 用一个比较恶心的方法避开单例（singletons）类
    if not @hooked_modules.include?(a_module) and a_module.to_s.slice(/\#\<.*\>/) == nil
      @hooked_modules.push(a_module)
      for a_method in a_module.instance_methods(hook_super)
        hook_instance_method(a_module, a_method)
      end
    end
  end
  #--------------------------------------------------------------------------
  # ● 用插入代码的办法监测一个实例方法
  #   a_module Module类
  #   a_method 方法的名称，String类
  #--------------------------------------------------------------------------
  def hook_instance_method(a_module, a_method)
    new_name = (HOOKED_METHOD_PREFIX + a_method.to_s).gsub(
      /\W+/){|matched| matched.to_sym.object_id}.to_sym
    if not a_module.method_defined?(new_name)
      a_module.send :alias_method, new_name, a_method
      a_module.class_eval("
      def #{a_method}(*args, &bloc)
        Method_Timer.trace_call('', 0, :#{a_method}, #{a_module})
        result = #{new_name}(*args, &bloc)
        Method_Timer.trace_return('', 0, :#{a_method}, #{a_module})
        return result
      end
      ")
    end
  end
  #--------------------------------------------------------------------------
  # ● 删除监测数据
  #--------------------------------------------------------------------------
  def clear_traces
    @method_traces = {}
  end
  #--------------------------------------------------------------------------
  # ● 跟踪方法调用
  #--------------------------------------------------------------------------
  def trace_call(file, line, id, classname)
    key = [id, classname]
    if @method_traces[key] == nil
      @method_traces[key] = Method_Trace.new(file, line, id, classname)
    end
    @method_traces[key].a_call
  end
  #--------------------------------------------------------------------------
  # ● 跟踪方法返回
  #--------------------------------------------------------------------------
  def trace_return(file, line, id, classname)
    key = [id, classname]
    if @method_traces[key] != nil
      @method_traces[key].a_return
    end
  end
  #--------------------------------------------------------------------------
  # ● 记录，按class排序
  #--------------------------------------------------------------------------
  def log_by_class
    begin
      file = File.open(LOG_FILE, 'a')
      write_welcome(file)
      write_header(file)
      classes = {}
      for trace in @method_traces.values
        if classes[trace.classname] == nil
          classes[trace.classname] = [trace]
        else
          classes[trace.classname].push(trace)
        end
      end
      for a_class in classes.keys
        write_class_info(a_class, file)
        classes[a_class].sort!
        for trace in classes[a_class]
          write_method_info(trace, file)
        end
      end
    ensure
      file.close
    end
  end
  #--------------------------------------------------------------------------
  # ● 记录，按时间排序
  #--------------------------------------------------------------------------
  def log_by_time
    begin
      file = File.open(LOG_FILE, 'a')
      write_welcome(file)
      write_header(file)
      for trace in @method_traces.values.sort
        write_method_info(trace, file)
      end
    ensure
      file.close
    end
  end
  #--------------------------------------------------------------------------
  # ● 写入欢迎信息
  #--------------------------------------------------------------------------
  def write_welcome(file)
    time = Time.now
    s = "\n╮(￣▽￣)╭ ╮(￣▽￣)╭ ╮(￣▽￣)╭ ╮(￣▽￣)╭ ╮(￣▽￣)╭ \n\n" +
    "#{time.year}年#{time.month}月#{time.mday}日 " + 
    "星期#{time.wday} " + 
    "#{time.hour}:#{time.min}:#{time.sec}\n\n"
    file.write(s)
  end
  #--------------------------------------------------------------------------
  # ● 写入分类信息
  #--------------------------------------------------------------------------
  def write_header(file)
    s = sprintf("\n  %-16s %-16s %10s %10s %10s\n\n", 'class', 'method', 'total time', 'calls', 'average')
    file.write(s)
  end
  #--------------------------------------------------------------------------
  # ● 写入类信息
  #--------------------------------------------------------------------------
  def write_class_info(a_class, file)
    if a_class == nil
      s = "\n\n"
    else
      s = "\n#{a_class.to_s}类\n\n"
    end
    file.write(s)
  end
  #--------------------------------------------------------------------------
  # ● 写入方法信息
  #--------------------------------------------------------------------------
  def write_method_info(trace, file)
    s = sprintf("  %-16s#%-16s %10.4f %10i %10.4f\n", trace.classname.to_s, trace.id, trace.total_time, trace.call_times, trace.average_time)
    file.write(s)
  end
end

#==============================================================================
# ■ Method_Trace
#------------------------------------------------------------------------------
#   方法监测
#==============================================================================

class Method_Trace
  #--------------------------------------------------------------------------
  # ● 实例变量
  #--------------------------------------------------------------------------
  attr_accessor :file, :line, :id, :classname, :total_time, :call_times
  #--------------------------------------------------------------------------
  # ● 初始化
  #--------------------------------------------------------------------------
  def initialize(file, line, id, classname)
    @file = file
    @line = line
    @id = id
    @classname = classname
    @time = nil
    @total_time = 0.0
    @call_times = 0
  end
  #--------------------------------------------------------------------------
  # ● 一次调用
  #--------------------------------------------------------------------------
  def a_call
    @time = Time.now
    #@time = Process.times
  end
  #--------------------------------------------------------------------------
  # ● 一次返回
  #--------------------------------------------------------------------------
  def a_return
    @total_time += Time.now - @time
    #times = Process.times
    #@total_time += times.utime + times.stime - @time.utime -  @time.stime
    @call_times += 1
  end
  #--------------------------------------------------------------------------
  # ● 输出
  #--------------------------------------------------------------------------
  def inspect
    return sprintf('%-10s %-10s %10.4f', id, classname.inspect, @total_time)
  end
  #--------------------------------------------------------------------------
  # ● 比较
  #--------------------------------------------------------------------------
  def <=>(other)
    return other.average_time <=> average_time
  end
  #--------------------------------------------------------------------------
  # ● 平均运行时间
  #--------------------------------------------------------------------------
  def average_time
    if @call_times == 0
      return 0.0
    else
      return @total_time / @call_times
    end
  end
end


Method_Timer.ini